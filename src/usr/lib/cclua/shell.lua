local M={}

local function split(line)
  local out={}
  local cur=""
  local quote=nil
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

local function prompt(ctx)
  local u=ctx.kernel.users.by_uid(ctx.process.uid)
  local name=(u and u.name) or tostring(ctx.process.uid)
  local host="cclua-server"
  local h=fs.open("etc/hostname","r")
  if h then host=(h.readLine() or host);h.close() end
  return name.."@"..host..":"..ctx.process.cwd..(ctx.process.uid==0 and "# " or "$ ")
end

local function builtin(ctx,args)
  local cmd=args[1]
  if cmd=="cd" then
    local target=args[2] or ((ctx.kernel.users.by_uid(ctx.process.uid) or {}).home) or "/"
    if target=="~" then target=((ctx.kernel.users.by_uid(ctx.process.uid) or {}).home) or "/" end
    if target:sub(1,1)~="/" then target=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..target) end
    target=ctx.kernel.vfs.normalize(target)
    if not ctx.kernel.vfs.exists(target) or not ctx.kernel.vfs.isDir(target) then
      print("bash: cd: "..target..": No such file or directory")
      return true,1
    end
    ctx.process.cwd=target
    return true,0
  elseif cmd=="pwd" then
    print(ctx.process.cwd);return true,0
  elseif cmd=="exit" then
    return true,tonumber(args[2]) or 0,"exit"
  elseif cmd=="clear" then
    term.clear();term.setCursorPos(1,1);return true,0
  elseif cmd=="export" then
    for i=2,#args do
      local k,v=args[i]:match("^([%w_]+)=(.*)$")
      if k then ctx.process.environment[k]=v end
    end
    return true,0
  elseif cmd=="help" then
    print("CCLUA shell builtins: cd pwd export clear exit help")
    print("External commands are loaded from /usr/bin and /usr/sbin.")
    return true,0
  end
  return false
end

local function run_external(ctx,args)
  local path=ctx.kernel.exec.resolve(args[1])
  if not path then
    print(args[1]..": command not found")
    return 127
  end
  local mod,err=ctx.kernel.exec.load(path)
  if not mod then
    print(args[1]..": "..tostring(err))
    return 126
  end
  local child,cerr=ctx.kernel.process.create{
    ppid=ctx.process.pid,
    name=args[1],
    uid=ctx.process.uid,
    gid=ctx.process.gid,
    groups=ctx.process.groups,
    cwd=ctx.process.cwd,
    environment=ctx.process.environment,
    capabilities=ctx.process.capabilities,
    argv=args,
    session_id=ctx.process.session_id,
    process_group=ctx.process.process_group
  }
  if not child then print("bash: spawn failed: "..tostring(cerr));return 1 end

  ctx.kernel.scheduler:add(child,function()
    local cctx={kernel=ctx.kernel,process=child}
    local sub={}
    for i=2,#args do sub[#sub+1]=args[i] end
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
  while true do
    term.setTextColor(colors.white)
    write(prompt(ctx))
    local line=read()
    if line==nil then return 0 end
    local args=split(line)
    if #args>0 then
      local handled,code,action=builtin(ctx,args)
      if not handled then code=run_external(ctx,args) end
      ctx.process.environment["?"]=tostring(code or 0)
      if action=="exit" then return code or 0 end
    end
  end
end

return M
