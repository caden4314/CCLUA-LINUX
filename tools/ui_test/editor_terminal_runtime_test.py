from pathlib import Path
from lupa import LuaRuntime

ROOT=Path(r"E:\Minecraft\CCLUA-LINUX")
lua=LuaRuntime(unpack_returned_tuples=True)
g=lua.globals()
g.py_read=lambda p:(ROOT/"src"/str(p).lstrip("/").replace("/","\\")).read_text(encoding="utf-8")

lua.execute(r'''
colors={
 white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
 gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
 green=8192,red=16384,black=32768
}
keys={
 escape=256,enter=257,tab=258,backspace=259,delete=261,right=262,left=263,
 down=264,up=265,pageUp=266,pageDown=267,home=268,["end"]=269,
 f2=291,f3=292,
 leftShift=340,leftCtrl=341,leftAlt=342,rightShift=344,rightCtrl=345,rightAlt=346,
 a=65,c=67,d=68,e=69,f=70,g=71,k=75,o=79,q=81,r=82,s=83,
 u=85,v=86,w=87,x=88,y=89,z=90
}

files={
 ["home/caden/doc.txt"]="hello world\nsecond line\nthird",
 ["home/caden/other.txt"]="other document",
}
fs={}
local function norm(p) return tostring(p or ""):gsub("^/","") end
function fs.exists(p) return files[norm(p)]~=nil or norm(p)=="home/caden" or norm(p)=="usr/bin" or norm(p)=="bin" end
function fs.isDir(p)
  p=norm(p)
  return p=="home/caden" or p=="usr/bin" or p=="bin"
end
function fs.getSize(p) return #(files[norm(p)] or "") end
function fs.getDir(p)
  p=norm(p):gsub("/+$","")
  return p:match("^(.*)/[^/]+$") or ""
end
function fs.combine(a,b)
  a=tostring(a or ""):gsub("^/",""):gsub("/+$","")
  b=tostring(b or ""):gsub("^/+","")
  if a=="" then return b end
  return a.."/"..b
end
function fs.makeDir(_) end
function fs.list(p)
  p=norm(p)
  if p=="usr/bin" then return {"cclua-status.lua","systemctl.lua","top.lua"} end
  if p=="bin" then return {"ls.lua","cat.lua"} end
  if p=="home/caden" then return {"doc.txt","other.txt"} end
  return {}
end
function fs.open(p,mode)
  p=norm(p)
  if tostring(mode):sub(1,1)=="r" then
    if files[p]==nil then return nil,"missing" end
    local value=files[p]
    return {readAll=function() return value end,close=function() end}
  end
  local buf=""
  return {
    write=function(s) buf=buf..tostring(s or "") end,
    close=function() files[p]=buf end,
  }
end
''')

lua.execute(r'''
mock_config={machine=function() return {hostname="test-client"} end}

function dofile(path)
  if path=="/usr/lib/cclua/config.lua" then return mock_config end
  local code=py_read(path)
  local fn,err=load(code,"@"..path,"t",_G)
  if not fn then error(err) end
  return fn()
end

ctx={process={cwd="/home/caden",uid=1000,pid=22}}
ctx.kernel={
  vfs={
    normalize=function(p)
      local absolute=tostring(p)
      absolute=absolute:gsub("//+","/")
      return absolute
    end,
    exists=function(p) return fs.exists(p) end,
    isDir=function(p) return fs.isDir(p) end,
  },
  exec={
    resolve=function(name)
      if name=="falsecmd" then return "/usr/bin/falsecmd.lua" end
      return nil
    end,
    load=function(path)
      if path=="/usr/bin/falsecmd.lua" then
        return {main=function() print("simulated failure");return 7 end}
      end
      return nil,"missing"
    end,
  },
}

term={
 current=function() return term end,
 redirect=function(_) end,
}
''')

lua.execute(r'''
editor=dofile("/usr/lib/cclua/desktop/apps/editor.lua")
ed=editor.new(ctx,{path="/home/caden/doc.txt"})
assert(ed.lines[1]=="hello world" and ed.lines[2]=="second line")
assert(editor.get_title(ed)=="doc.txt - Text Editor")

-- Basic edit, undo, redo.
editor.event(ctx,ed,"char","!",nil,nil,nil,nil,80,24)
assert(ed.lines[1]=="!hello world" and ed.dirty)
editor.event(ctx,ed,"key",keys.leftCtrl,nil,nil,nil,nil,80,24)
editor.event(ctx,ed,"key",keys.z,nil,nil,nil,nil,80,24)
editor.event(ctx,ed,"key_up",keys.leftCtrl,nil,nil,nil,nil,80,24)
assert(ed.lines[1]=="hello world")
editor.event(ctx,ed,"key",keys.leftCtrl,nil,nil,nil,nil,80,24)
editor.event(ctx,ed,"key",keys.y,nil,nil,nil,nil,80,24)
editor.event(ctx,ed,"key_up",keys.leftCtrl,nil,nil,nil,nil,80,24)
assert(ed.lines[1]=="!hello world")

-- Multiline paste including a trailing newline must preserve one trailing row.
ed.row=1;ed.col=1
editor.event(ctx,ed,"paste","A\nB\n",nil,nil,nil,nil,80,24)
assert(ed.lines[1]=="A" and ed.lines[2]=="B" and ed.lines[3]:sub(1,1)=="!")

-- Find selects the requested text.
editor.event(ctx,ed,"key",keys.leftCtrl,nil,nil,nil,nil,80,24)
editor.event(ctx,ed,"key",keys.f,nil,nil,nil,nil,80,24)
editor.event(ctx,ed,"key_up",keys.leftCtrl,nil,nil,nil,nil,80,24)
for ch in ("second"):gmatch(".") do editor.event(ctx,ed,"char",ch,nil,nil,nil,nil,80,24) end
editor.event(ctx,ed,"key",keys.enter,nil,nil,nil,nil,80,24)
assert(ed.findTerm=="second")
assert(ed.lines[ed.row]:find("second",1,true))

-- Dirty documents cannot be silently replaced.
local opened=editor.open(ctx,ed,{path="/home/caden/other.txt"})
assert(opened==false and ed.mode=="confirm-open")
editor.event(ctx,ed,"char","n",nil,nil,nil,nil,80,24)
assert(ed.path=="/home/caden/doc.txt")
assert(editor.before_close(ctx,ed)==false)

-- Ctrl+Q requires confirmation then returns a forced close action.
editor.event(ctx,ed,"key",keys.leftCtrl,nil,nil,nil,nil,80,24)
local first=editor.event(ctx,ed,"key",keys.q,nil,nil,nil,nil,80,24)
local second=editor.event(ctx,ed,"key",keys.q,nil,nil,nil,nil,80,24)
editor.event(ctx,ed,"key_up",keys.leftCtrl,nil,nil,nil,nil,80,24)
assert(first==true)
assert(type(second)=="table" and second.action=="close_self" and second.force==true)
''')

lua.execute(r'''
terminal=dofile("/usr/lib/cclua/desktop/apps/terminal.lua")
sh=terminal.new(ctx)

-- Cursor editing in the middle of a command line.
for ch in ("abc"):gmatch(".") do terminal.event(ctx,sh,"char",ch) end
terminal.event(ctx,sh,"key",keys.left)
terminal.event(ctx,sh,"key",keys.left)
terminal.event(ctx,sh,"char","X")
assert(sh.input=="aXbc" and sh.inputPos==3,"mid-edit "..tostring(sh.input).." pos "..tostring(sh.inputPos))

-- Ctrl+A / Ctrl+E / Ctrl+U.
terminal.event(ctx,sh,"key",keys.leftCtrl)
terminal.event(ctx,sh,"key",keys.a)
assert(sh.inputPos==1,"ctrl-a pos "..tostring(sh.inputPos))
terminal.event(ctx,sh,"key",keys.e)
assert(sh.inputPos==#sh.input+1,"ctrl-e pos "..tostring(sh.inputPos))
terminal.event(ctx,sh,"key",keys.u)
assert(sh.input=="","ctrl-u input "..tostring(sh.input))
terminal.event(ctx,sh,"key_up",keys.leftCtrl)

-- Tab completion from builtins.
for ch in ("hist"):gmatch(".") do terminal.event(ctx,sh,"char",ch) end
terminal.event(ctx,sh,"key",keys.tab)
assert(sh.input=="history ","completion "..tostring(sh.input))

-- Run builtins and preserve history.
terminal.event(ctx,sh,"key",keys.enter)
assert(sh.lastStatus==0 and #sh.history==1,"history run status "..tostring(sh.lastStatus).." count "..tostring(#sh.history))
terminal.event(ctx,sh,"key",keys.up)
assert(sh.input=="history","history recall "..tostring(sh.input))

-- Unknown command sets 127 and changes prompt status.
sh.input="does-not-exist";sh.inputPos=#sh.input+1
terminal.event(ctx,sh,"key",keys.enter)
assert(sh.lastStatus==127,"unknown status "..tostring(sh.lastStatus))

-- Scrollback must move backwards on mouse wheel up.
for i=1,8 do
  sh.input="help";sh.inputPos=5
  terminal.event(ctx,sh,"key",keys.enter)
end
terminal.event(ctx,sh,"mouse_scroll",-1)
assert(sh.viewOffset>0,"scroll up offset "..tostring(sh.viewOffset))
terminal.event(ctx,sh,"mouse_scroll",1)
assert(sh.viewOffset>=0,"scroll down offset "..tostring(sh.viewOffset))

print("EDITOR_TERMINAL_RUNTIME_OK")
print("EDITOR_UNDO_REDO_PASS")
print("EDITOR_MULTILINE_PASTE_PASS")
print("EDITOR_FIND_DIRTY_GUARD_PASS")
print("TERMINAL_LINE_EDIT_PASS")
print("TERMINAL_COMPLETION_HISTORY_PASS")
print("TERMINAL_SCROLLBACK_STATUS_PASS")
''')