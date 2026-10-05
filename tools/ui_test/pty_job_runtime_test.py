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
function colors.toBlit(c)
 local n,v=0,c
 while v>1 do v=v/2;n=n+1 end
 return ("%x"):format(n)
end
queued={}
os={
 epoch=function(_) return 1000 end,
 queueEvent=function(...) queued[#queued+1]={...} end,
}
local native={name="native",write=function() end}
term={
 _current=native,
 current=function() return term._current end,
 redirect=function(t) local old=term._current;term._current=t;return old end,
 nativePaletteColor=function(_) return 1,1,1 end,
}
for _,name in ipairs({"setCursorPos","setCursorBlink","setTextColor","setBackgroundColor",
 "getCursorPos","getSize","clear","clearLine","scroll","blit"}) do
 term[name]=function(...) return term._current[name](...) end
end
function write(s) return term._current.write(s) end
function print(s)
 term._current.write(tostring(s or ""))
 term._current.write("\n")
end
''')

lua.execute(r'''
function dofile(path)
 local code=py_read(path)
 local fn,err=load(code,"@"..path,"t",_G)
 if not fn then error(err) end
 return fn()
end

kernel={}
kernel.log={write=function() end}
kernel.capabilities={
 has=function() return true end,
 root=function() return {} end,
}
kernel.signals=dofile("/kernel/signals.lua")
kernel.process=dofile("/kernel/process.lua")
kernel.pty=dofile("/kernel/pty.lua")
kernel.scheduler=dofile("/kernel/scheduler.lua").new(kernel)
kernel.syscalls=dofile("/kernel/syscall.lua").new(kernel)

parent=assert(kernel.process.create{
 pid=1,name="desktop",uid=1000,gid=1000,cwd="/home/caden",
 environment={},capabilities={},session_id=1,process_group=1
})

kernel.exec={}
function kernel.exec.resolve(name) return "/virtual/"..name end
function kernel.exec.load(path)
 local name=path:match("([^/]+)$")
 if name=="interactive" then
  return {main=function(ctx,args)
   print("READY")
   ctx.pty:set_alternate_screen(true)
   term.setCursorPos(3,2)
   term.setCursorBlink(true)
   term.setTextColor(colors.cyan)
   write("ALT")
   local ev,ch=coroutine.yield("wait_event","char")
   print("GOT:"..tostring(ch))
   ctx.pty:set_alternate_screen(false)
   print("DONE")
   return 7
  end}
 elseif name=="waiter" then
  return {main=function(ctx,args)
   print("WAIT")
   local ev,ch=coroutine.yield("wait_event","char")
   print("END:"..tostring(ch))
   return 0
  end}
 end
 return nil,"ENOEXEC"
end
''')

lua.execute(r'''
Jobs=dofile("/usr/lib/cclua/jobs.lua")
ctx={kernel=kernel,process=parent}
mgr=Jobs.new(ctx,{cols=20,rows=6})

job=assert(mgr:spawn({"interactive"},{cwd="/home/caden"}))
kernel.scheduler:dispatch({})
assert(job.pty.use_alt==true,"alternate screen not enabled")
assert(job.pty.cursor_x==6 and job.pty.cursor_y==2,
 "cursor state missing "..tostring(job.pty.cursor_x)..","..tostring(job.pty.cursor_y))
assert(job.pty.cursor_blink==true,"cursor blink missing")

kernel.scheduler:dispatch({"char","BAD"})
assert(kernel.process.get(job.pid).state=="waiting","unexpected PTY input delivery")

assert(mgr:send(job,{"char","X"}))
kernel.scheduler:dispatch({})
mgr:refresh()
assert(job.done and job.exit_code==7,"interactive job did not exit cleanly")
assert(job.pty.use_alt==false,"alternate screen not restored")
local snap=job.pty:snapshot()
local all=""
for _,row in ipairs(snap.screen) do all=all..row.ch.."\n" end
assert(all:find("DONE",1,true),"final PTY output missing")

job2=assert(mgr:spawn({"waiter"},{background=true}))
kernel.scheduler:dispatch({})
assert(mgr:stop(job2))
assert(kernel.process.get(job2.pid).state=="stopped","SIGSTOP failed")
assert(mgr:background_job(job2))
assert(kernel.process.get(job2.pid).state=="waiting","SIGCONT failed")
assert(mgr:send(job2,{"char","Y"}))
kernel.scheduler:dispatch({})
mgr:refresh()
assert(job2.done and job2.exit_code==0,"continued job failed")

job3=assert(mgr:spawn({"waiter"},{}))
kernel.scheduler:dispatch({})
assert(mgr:signal(job3,"INT"))
mgr:refresh()
assert(job3.done and job3.exit_code==130,"SIGINT exit code incorrect")
''')

lua.execute(r'''
p=kernel.pty.new(8,3)
p.term.write("one\ntwo\nthree\nfour")
local sc=p:take_scrollback()
assert(#sc>=1,"PTY scrollback missing")
assert(p:resize(12,4)==true,"PTY resize not reported")
local s=p:snapshot()
assert(s.cols==12 and s.rows==4,"PTY resize dimensions wrong")

print("PTY_JOB_RUNTIME_OK")
print("PTY_FOCUSED_INPUT_PASS")
print("PTY_ALT_SCREEN_CURSOR_PASS")
print("PTY_PROCESS_GROUP_SIGNAL_PASS")
print("PTY_RESIZE_SCROLLBACK_PASS")
''')
print("PTY_JOB_RUNTIME_OK")
print("PTY_FOCUSED_INPUT_PASS")
print("PTY_ALT_SCREEN_CURSOR_PASS")
print("PTY_PROCESS_GROUP_SIGNAL_PASS")
print("PTY_RESIZE_SCROLLBACK_PASS")

lua.execute(r'''
local nextTimer=40
os.startTimer=function(_)
 nextTimer=nextTimer+1
 return nextTimer
end
os.clock=function() return 12 end
os.date=function(_) return "12:00:00" end
kernel.services={list=function() return {} end}
kernel.users={by_uid=function(_,uid) return {name=uid==1000 and "caden" or "root"} end}

local topmod=dofile("/usr/bin/top.lua")
local topPty=kernel.pty.new(48,12)
local topProc=assert(kernel.process.create{
 name="top",ppid=parent.pid,uid=1000,gid=1000,cwd="/home/caden",
 environment={},capabilities={},session_id=1,pty=topPty
})
kernel.scheduler:add(topProc,function()
 return topmod.main({kernel=kernel,process=topProc,pty=topPty},{})
end)
kernel.scheduler:dispatch({})
assert(topPty.use_alt==true,"top did not enter alternate screen")
local before=topProc.cpu_resumes

assert(kernel.scheduler:send_event(topProc.pid,{"timer",41}))
kernel.scheduler:dispatch({})
assert(topProc.state=="waiting","top timer refresh did not return to wait state")
assert(topProc.cpu_resumes>before,"top timer event did not resume process")

assert(kernel.scheduler:send_event(topProc.pid,{"char","q"}))
kernel.scheduler:dispatch({})
assert(kernel.process.is_terminal(topProc),"top q did not exit")
assert(topPty.use_alt==false,"top did not restore alternate screen")
''')
print("PTY_TOP_TIMER_REFRESH_PASS")
