local M={}
local config=dofile("/usr/lib/cclua/config.lua")
local ui=dofile("/usr/lib/cclua/cli_ui.lua")

local function split(line)
  local out,cur,quote={},"",nil
  local i=1
  while i<=#line do
    local c=line:sub(i,i)
    if quote then
      if c==quote then quote=nil
      elseif c=="\\" and i<#line then i=i+1;cur=cur..line:sub(i,i)
      else cur=cur..c end
    else
      if c=="'" or c=='"' then quote=c
      elseif c:match("%s") then
        if #cur>0 then out[#out+1]=cur;cur="" end
      elseif c=="\\" and i<#line then i=i+1;cur=cur..line:sub(i,i)
      else cur=cur..c end
    end
    i=i+1
  end
  if #cur>0 then out[#out+1]=cur end
  return out
end

local function username(ctx)
  local u=ctx.kernel.users.by_uid(ctx.process.uid)
  return (u and u.name) or tostring(ctx.process.uid)
end

local function hostname()
  local m=config.machine()
  return m.hostname or "cclua-server"
end

local function display_path(ctx)
  local cwd=tostring(ctx.process.cwd or "/")
  local home=((ctx.kernel.users.by_uid(ctx.process.uid) or {}).home) or "/"
  if cwd==home then return "~" end
  if home~="/" and cwd:sub(1,#home+1)==home.."/" then return "~/"..cwd:sub(#home+2) end
  return cwd
end

local function draw_prompt(ctx,last)
  local user=username(ctx)
  term.setTextColor(ctx.process.uid==0 and colors.red or colors.lime)
  write(user)
  term.setTextColor(colors.lightGray)
  write("@")
  term.setTextColor(colors.lightBlue)
  write(hostname())
  term.setTextColor(colors.white)
  write(":")
  term.setTextColor(colors.cyan)
  write(display_path(ctx))
  if last and last~=0 then
    term.setTextColor(colors.red)
    write(" ["..tostring(last).."]")
  end
  term.setTextColor(colors.yellow)
  write(ctx.process.uid==0 and "# " or "$ ")
  term.setTextColor(colors.white)
end

local function banner(ctx)
  local m=config.machine()
  local status=config.read_json("/var/lib/cclua/status.json",{state="BOOTING"}) or {}
  local net=config.read_json("/var/lib/cclua/network-health.json",{state="CHECKING"}) or {}
  local post=config.read_json("/var/lib/cclua/post.json",{state="UNKNOWN"}) or {}

  term.setTextColor(colors.white)
  print("Ubuntu 22.04.5 LTS [CCLUA]  "..hostname())
  term.setTextColor(colors.gray)
  print(("ID %d  |  %s  |  %s"):format(
    os.getComputerID(),tostring(m.role or "server"),tostring(m.address or "unconfigured")
  ))

  term.setTextColor(ui.state_color(status.state));write("SYSTEM "..tostring(status.state or "BOOTING"))
  term.setTextColor(colors.gray);write("  |  ")
  term.setTextColor(ui.state_color(net.state));write("NET "..tostring(net.state or "CHECKING"))
  term.setTextColor(colors.gray);write("  |  ")
  term.setTextColor(ui.state_color(post.state));print("POST "..tostring(post.state or "UNKNOWN"))

  term.setTextColor(colors.gray)
  print("Kernel "..ctx.kernel.version.version.."  |  help: 'help'  |  health: 'cclua-status'")
  print("")
  term.setTextColor(colors.white)
end

local function builtin(ctx,args)
  local cmd=args[1]
  if cmd=="cd" then
    local target=args[2] or ((ctx.kernel.users.by_uid(ctx.process.uid) or {}).home) or "/"
    if target=="~" then target=((ctx.kernel.users.by_uid(ctx.process.uid) or {}).home) or "/" end
    if target:sub(1,1)~="/" then target=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..target) end
    target=ctx.kernel.vfs.normalize(target)
    if not ctx.kernel.vfs.exists(target) or not ctx.kernel.vfs.isDir(target) then
      ui.error("cd: "..target..": No such file or directory","Check the path or use 'pwd' and 'ls'.")
      return true,1
    end
    ctx.process.cwd=target
    return true,0
  elseif cmd=="pwd" then print(ctx.process.cwd);return true,0
  elseif cmd=="exit" then return true,tonumber(args[2]) or 0,"exit"
  elseif cmd=="clear" then term.clear();term.setCursorPos(1,1);return true,0
  elseif cmd=="export" then
    for i=2,#args do local k,v=args[i]:match("^([%w_]+)=(.*)$");if k then ctx.process.environment[k]=v end end
    return true,0
  elseif cmd=="help" then
    ui.heading("CCLUA shell commands")
    print("  Shell       cd  pwd  export  clear  exit  help")
    print("  Files       ls  cat  cp  mv  rm  mkdir  grep  find")
    print("  Processes   ps  top  kill")
    print("  System      cclua-status  systemctl  journalctl  dmesg")
    print("  Network     ip  ping  resolvectl  hostnamectl")
    print("  Fleet       cclua-managerctl  cclua-lightctl  cclua-appctl")
    print("  Packages    apt  dpkg")
    ui.dim("Tip: use Up/Down for command history.")
    return true,0
  end
  return false
end

local function run_external(ctx,args)
  local path=ctx.kernel.exec.resolve(args[1])
  if not path then
    ui.error(args[1]..": command not found","Run 'help' for common commands.")
    return 127
  end
  local mod,err=ctx.kernel.exec.load(path)
  if not mod then term.setTextColor(colors.red);print(args[1]..": "..tostring(err));term.setTextColor(colors.white);return 126 end
  local child,cerr=ctx.kernel.process.create{
    ppid=ctx.process.pid,name=args[1],uid=ctx.process.uid,gid=ctx.process.gid,
    groups=ctx.process.groups,cwd=ctx.process.cwd,environment=ctx.process.environment,
    capabilities=ctx.process.capabilities,argv=args,session_id=ctx.process.session_id,
    process_group=ctx.process.process_group
  }
  if not child then print("bash: spawn failed: "..tostring(cerr));return 1 end

  ctx.kernel.scheduler:add(child,function()
    local cctx={kernel=ctx.kernel,process=child}
    local sub={};for i=2,#args do sub[#sub+1]=args[i] end
    local ok,res=pcall(mod.main,cctx,sub)
    if not ok then error(res,0) end
    return tonumber(res) or 0
  end)

  while child.state~="exited" and child.state~="killed" and child.state~="crashed" do
    local ev,pid=coroutine.yield("wait_event","cclua_process_exit")
    if ev=="cclua_process_exit" and pid==child.pid then break end
  end
  return child.exit_code or 1
end

function M.run(ctx,argv)
  ctx.process.environment.PATH=ctx.process.environment.PATH or "/usr/bin:/usr/sbin:/bin:/sbin"
  ctx.process.environment.HOME=ctx.process.environment.HOME or (((ctx.kernel.users.by_uid(ctx.process.uid) or {}).home) or "/")
  local history={}
  local last=0
  banner(ctx)
  while true do
    draw_prompt(ctx,last)
    local line=read(nil,history)
    if line==nil then return 0 end
    if line~="" then history[#history+1]=line end
    local args=split(line)
    if #args>0 then
      local handled,code,action=builtin(ctx,args)
      if not handled then code=run_external(ctx,args) end
      last=code or 0
      ctx.process.environment["?"]=tostring(last)
      if action=="exit" then return last end
    end
  end
end

return M
