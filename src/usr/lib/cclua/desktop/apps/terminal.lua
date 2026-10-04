local M={}
local exec=dofile("/usr/lib/cclua/exec.lua")

local function push(st,line)
  st.lines[#st.lines+1]=tostring(line or "")
  while #st.lines>200 do table.remove(st.lines,1) end
end

function M.new(ctx)
  return {
    title="Terminal",icon=">_",cwd=ctx.process.cwd or "/home/caden",
    input="",lines={
      "Ubuntu 22.04.5 LTS (CCLUA)",
      "Type 'help' for commands.",
      ""
    }
  }
end

local function words(line)
  local out={}
  for w in tostring(line):gmatch("%S+") do out[#out+1]=w end
  return out
end

local function capture(st)
  local t={x=1,y=1,w=80,h=40,fg=colors.white,bg=colors.black}
  function t.write(s)
    s=tostring(s or "")
    local parts={}
    for part in (s.."\n"):gmatch("(.-)\n") do parts[#parts+1]=part end
    for i,part in ipairs(parts) do
      if part~="" then push(st,part) end
      if i<#parts then t.x=1;t.y=t.y+1 else t.x=t.x+#part end
    end
  end
  function t.blit(s) t.write(s) end
  function t.clear() end
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
  push(st,"caden@test-client:"..st.cwd.."$ "..line)

  if argv[1]=="clear" then st.lines={};return end
  if argv[1]=="pwd" then push(st,st.cwd);return end
  if argv[1]=="cd" then
    local target=argv[2] or "/home/caden"
    if target:sub(1,1)~="/" then target=ctx.kernel.vfs.normalize(st.cwd.."/"..target) end
    target=ctx.kernel.vfs.normalize(target)
    if ctx.kernel.vfs.exists(target) and ctx.kernel.vfs.isDir(target) then st.cwd=target
    else push(st,"bash: cd: "..target..": No such directory") end
    return
  end
  if argv[1]=="help" then
    push(st,"Builtins: cd pwd clear help")
    push(st,"All CCLUA commands are available: ls cat ps ip apt ...")
    return
  end

  local path=ctx.kernel.exec.resolve(argv[1])
  if not path then push(st,argv[1]..": command not found");return end
  local mod,err=ctx.kernel.exec.load(path)
  if not mod then push(st,argv[1]..": "..tostring(err));return end
  local args={};for i=2,#argv do args[#args+1]=argv[i] end
  local old=term.current()
  local cap=capture(st)
  term.redirect(cap)
  local oldcwd=ctx.process.cwd
  ctx.process.cwd=st.cwd
  local ok,res=pcall(mod.main,ctx,args)
  ctx.process.cwd=oldcwd
  term.redirect(old)
  if not ok then push(st,"error: "..tostring(res)) end
end

function M.draw(ctx,st,ui,x,y,w,h,active)
  ui.fill(x,y,x+w-1,y+h-1,colors.black,colors.white)
  local body=h-2
  local start=math.max(1,#st.lines-body+1)
  local row=0
  for i=start,#st.lines do
    row=row+1
    ui.text(x+1,y+row-1,st.lines[i]:sub(1,math.max(1,w-2)),colors.lightGray,colors.black)
  end
  local prompt="caden@test-client:"..st.cwd.."$ "..st.input
  ui.text(x+1,y+h-1,prompt:sub(math.max(1,#prompt-w+3)),colors.white,colors.black)
  if active then ui.cursor=x+math.min(w-2,#prompt+1);ui.cursor_y=y+h-1 end
end

function M.event(ctx,st,ev,a,b,c)
  if ev=="char" then st.input=st.input..tostring(a);return true end
  if ev=="key" then
    if a==keys.backspace then st.input=st.input:sub(1,-2);return true end
    if a==keys.enter then
      local line=st.input;st.input=""
      run_command(ctx,st,line)
      return true
    end
  end
  return false
end

return M
