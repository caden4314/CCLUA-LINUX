local M={}
local config=dofile("/usr/lib/cclua/config.lua")

local function push(st,line,fg,bg)
  st.lines[#st.lines+1]={
    text=tostring(line or ""),
    fg=fg or colors.lightGray,
    bg=bg or colors.black,
  }
  while #st.lines>500 do table.remove(st.lines,1) end
end

local function pretty_path(path)
  path=tostring(path or "/")
  if path=="/home/caden" then return "~" end
  if path:sub(1,12)=="/home/caden/" then return "~/"..path:sub(13) end
  return path
end

function M.new(ctx)
  return {
    title="Terminal",icon="T",
    cwd=ctx.process.cwd or "/home/caden",
    input="",lines={
      {text="Ubuntu 22.04.5 LTS",fg=colors.white,bg=colors.black},
      {text="CCLUA terminal  |  type 'help' for commands",fg=colors.gray,bg=colors.black},
      {text="",fg=colors.lightGray,bg=colors.black}
    },
    history={},historyIndex=nil,
  }
end

function M.snapshot(st)
  return {cwd=st.cwd}
end

function M.open(ctx,st,opts)
  if opts and opts.cwd then st.cwd=opts.cwd return true end
  return false
end

local function words(line)
  local out={}
  local buf={}
  local quote=nil
  local escape=false
  local function flush()
    if #buf>0 then out[#out+1]=table.concat(buf);buf={} end
  end
  for i=1,#line do
    local ch=line:sub(i,i)
    if escape then
      buf[#buf+1]=ch
      escape=false
    elseif ch=="\\" then
      escape=true
    elseif quote then
      if ch==quote then quote=nil else buf[#buf+1]=ch end
    elseif ch=="'" or ch=='"' then
      quote=ch
    elseif ch:match("%s") then
      flush()
    else
      buf[#buf+1]=ch
    end
  end
  flush()
  return out
end

local function capture(st)
  local t={x=1,y=1,w=100,h=50,fg=colors.white,bg=colors.black}
  local pending=""
  function t.write(s)
    s=tostring(s or "")
    pending=pending..s
    while true do
      local p=pending:find("\n",1,true)
      if not p then break end
      push(st,pending:sub(1,p-1),t.fg,t.bg)
      pending=pending:sub(p+1)
      t.x=1;t.y=t.y+1
    end
    if pending~="" then
      -- Most CCLUA commands write complete lines, but keep partial output visible.
      local last=st.lines[#st.lines]
      if #st.lines==0 or type(last)~="table" or last.text~=pending then
        push(st,pending,t.fg,t.bg)
      end
      pending=""
    end
  end
  function t.blit(s) t.write(s) end
  function t.clear() st.lines={} end
  function t.clearLine() end
  function t.getCursorPos() return t.x,t.y end
  function t.setCursorPos(x,y) t.x=x;t.y=y end
  function t.setCursorBlink() end
  function t.isColor() return true end
  t.isColour=t.isColor
  function t.getSize() return t.w,t.h end
  function t.scroll() end
  function t.setTextColor(c) t.fg=c end
  t.setTextColour=t.setTextColor
  function t.getTextColor() return t.fg end
  t.getTextColour=t.getTextColor
  function t.setBackgroundColor(c) t.bg=c end
  t.setBackgroundColour=t.setBackgroundColor
  function t.getBackgroundColor() return t.bg end
  t.getBackgroundColour=t.getBackgroundColor
  return t
end

local function run_command(ctx,st,line)
  local argv=words(line)
  if #argv==0 then return end

  st.history[#st.history+1]=line
  while #st.history>100 do table.remove(st.history,1) end
  st.historyIndex=nil

  local host=(config.machine().hostname or "test-client")
  local prompt="caden@"..host..":"..pretty_path(st.cwd).."$ "
  push(st,prompt..line,colors.white,colors.black)

  if argv[1]=="clear" then st.lines={};return end
  if argv[1]=="pwd" then push(st,st.cwd);return end
  if argv[1]=="cd" then
    local target=argv[2] or "/home/caden"
    if target=="~" then target="/home/caden"
    elseif target:sub(1,2)=="~/" then target="/home/caden/"..target:sub(3)
    elseif target:sub(1,1)~="/" then target=ctx.kernel.vfs.normalize(st.cwd.."/"..target) end
    target=ctx.kernel.vfs.normalize(target)
    if ctx.kernel.vfs.exists(target) and ctx.kernel.vfs.isDir(target) then
      st.cwd=target
    else
      push(st,"bash: cd: "..target..": No such file or directory",colors.red)
    end
    return
  end
  if argv[1]=="history" then
    local first=math.max(1,#st.history-19)
    for i=first,#st.history do push(st,("%3d  %s"):format(i,st.history[i])) end
    return
  end
  if argv[1]=="help" then
    push(st,"Builtins: cd pwd clear history help")
    push(st,"Common commands: ls cat ps ip apt dpkg uname systemctl")
    push(st,"Shortcuts: Up/Down history, Ctrl+L clear, Ctrl+Alt+T new terminal")
    return
  end

  local path=ctx.kernel.exec.resolve(argv[1])
  if not path then
    push(st,argv[1]..": command not found",colors.red)
    push(st,"Try 'help' for common commands.",colors.gray)
    return
  end
  local mod,err=ctx.kernel.exec.load(path)
  if not mod then push(st,argv[1]..": "..tostring(err),colors.red);return end

  local args={}
  for i=2,#argv do args[#args+1]=argv[i] end
  local old=term.current()
  local cap=capture(st)
  term.redirect(cap)
  local oldcwd=ctx.process.cwd
  ctx.process.cwd=st.cwd
  local ok,res=pcall(mod.main,ctx,args)
  ctx.process.cwd=oldcwd
  term.redirect(old)
  if not ok then push(st,"Error: "..tostring(res),colors.red) end
end

local function history_move(st,delta)
  if #st.history==0 then return end
  if st.historyIndex==nil then st.historyIndex=#st.history+1 end
  st.historyIndex=math.max(1,math.min(#st.history+1,st.historyIndex+delta))
  if st.historyIndex>#st.history then st.input=""
  else st.input=st.history[st.historyIndex] end
end

function M.draw(ctx,st,ui,x,y,w,h,active)
  ui.fill(x,y,x+w-1,y+h-1,colors.black,colors.white)

  local body=math.max(1,h-2)
  local start=math.max(1,#st.lines-body+1)
  local row=0
  for i=start,#st.lines do
    row=row+1
    if row>body then break end
    local entry=st.lines[i]
    local text=type(entry)=="table" and entry.text or tostring(entry or "")
    local fg=type(entry)=="table" and entry.fg or colors.lightGray
    local bg=type(entry)=="table" and entry.bg or colors.black
    ui.text(x+1,y+row-1,text:sub(1,math.max(1,w-2)),fg,bg)
  end

  ui.fill(x,y+h-1,x+w-1,y+h-1,colors.black,colors.white)
  local host=(config.machine().hostname or "test-client")
  local user="caden"
  local path=pretty_path(st.cwd)
  local fixed=user.."@"..host..":"..path.."$ "
  local full=fixed..st.input
  local visible=full
  if #visible>w-2 then
    visible=visible:sub(-(w-2))
    ui.text(x+1,y+h-1,visible,colors.white,colors.black)
  else
    local px=x+1
    ui.text(px,y+h-1,user,colors.lime,colors.black);px=px+#user
    ui.text(px,y+h-1,"@",colors.lightGray,colors.black);px=px+1
    ui.text(px,y+h-1,host,colors.lightBlue,colors.black);px=px+#host
    ui.text(px,y+h-1,":",colors.white,colors.black);px=px+1
    ui.text(px,y+h-1,path,colors.cyan,colors.black);px=px+#path
    ui.text(px,y+h-1,"$ ",colors.yellow,colors.black);px=px+2
    ui.text(px,y+h-1,st.input,colors.white,colors.black)
  end

  if active then
    ui.cursor=x+math.min(w-2,#visible+1)
    ui.cursor_y=y+h-1
  end
end

function M.event(ctx,st,ev,a,b,c)
  if ev=="char" then
    st.input=st.input..tostring(a)
    return true
  end

  if ev=="key" then
    if a==keys.backspace then
      st.input=st.input:sub(1,-2)
      return true
    end
    if a==keys.enter then
      local line=st.input
      st.input=""
      run_command(ctx,st,line)
      return true
    end
    if a==keys.up then history_move(st,-1);return true end
    if a==keys.down then history_move(st,1);return true end
    if a==keys.home then st.input="";return true end
    if a==keys.l and (keys.leftCtrl or keys.rightCtrl) then
      -- Modifier state is owned by the compositor, so Ctrl+L is handled there.
      return false
    end
  end
  return false
end

return M
