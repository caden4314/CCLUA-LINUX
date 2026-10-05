from pathlib import Path
from lupa import LuaRuntime

ROOT=Path(r"E:\Minecraft\CCLUA-LINUX")
lua=LuaRuntime(unpack_returned_tuples=True)
g=lua.globals()
g.py_read=lambda p:(ROOT/"src"/str(p).lstrip("/").replace("/","\\")).read_text(encoding="utf-8")

lua.execute(r'''
colors={white=1,lightGray=256,cyan=512,red=16384,black=32768}
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
local native={write=function() end,getSize=function() return 80,24 end}
term={_current=native}
function term.current() return term._current end
function term.redirect(t) local o=term._current;term._current=t;return o end
function term.getTextColor() return colors.white end
function term.setTextColor(_) end
function write(s) return term._current.write(tostring(s or "")) end
function print(s) term._current.write(tostring(s or "").."\n") end

function dofile(path)
 local code=py_read(path)
 local fn,err=load(code,"@"..path,"t",_G)
 if not fn then error(err) end
 return fn()
end

files={
 ["/in.txt"]="alpha\nbeta\nalpine\ngamma\nalpaca\n",
}
local function norm(p)
 p=tostring(p or ""):gsub("\\","/")
 if p:sub(1,1)~="/" then p="/"..p end
 p=p:gsub("//+","/")
 return p
end
kernel={}
kernel.log={write=function() end}
kernel.capabilities={has=function() return true end,root=function() return {} end}
kernel.vfs={}
function kernel.vfs.normalize(p) return norm(p) end
function kernel.vfs.open(path,mode)
 path=norm(path)
 mode=mode or "r"
 if mode=="r" then
  if files[path]==nil then return nil,"ENOENT" end
  local data=files[path]
  local pos=1
  return {
   readAll=function() return data end,
   readLine=function()
    if pos>#data then return nil end
    local p=data:find("\n",pos,true)
    if not p then local s=data:sub(pos);pos=#data+1;return s end
    local s=data:sub(pos,p-1);pos=p+1;return s
   end,
   close=function() end,
  }
 end
 local buf=mode=="a" and (files[path] or "") or ""
 return {
  write=function(s) buf=buf..tostring(s or "") end,
  close=function() files[path]=buf end,
 }
end
kernel.signals=dofile("/kernel/signals.lua")
kernel.process=dofile("/kernel/process.lua")
kernel.streams=dofile("/kernel/streams.lua")
kernel.scheduler=dofile("/kernel/scheduler.lua").new(kernel)
kernel.syscalls=dofile("/kernel/syscall.lua").new(kernel)

kernel.exec={}
function kernel.exec.resolve(name)
 return "/usr/bin/"..tostring(name)..".lua"
end
function kernel.exec.load(path)
 local ok,mod=pcall(dofile,path)
 if not ok then return nil,mod end
 return mod
end

sink={data=""}
function sink:write(s) self.data=self.data..tostring(s or "");return true end
function sink:close() end
baseTerm=kernel.streams.terminal(sink,nil)
parent=assert(kernel.process.create{
 pid=1,name="sh",uid=1000,gid=1000,cwd="/",
 environment={},capabilities={},session_id=1,process_group=1,
 stdout=sink,stderr=sink,terminal=baseTerm,fd={[1]=sink,[2]=sink}
})

pipeline=dofile("/usr/lib/cclua/pipeline.lua")

function run_line(line)
 local p=assert(kernel.process.create{
  ppid=1,name="pipeline-test",uid=1000,gid=1000,cwd="/",
  environment={},capabilities={},session_id=1,process_group=100,
  stdout=sink,stderr=sink,terminal=baseTerm,fd={[1]=sink,[2]=sink}
 })
 kernel.scheduler:add(p,function()
  return pipeline.run({kernel=kernel,process=p},line)
 end)
 local guard=0
 while not kernel.process.is_terminal(p) and guard<200 do
  guard=guard+1
  kernel.scheduler:dispatch({})
  while #queued>0 do
   local ev=table.remove(queued,1)
   kernel.scheduler:dispatch(ev)
  end
 end
 assert(guard<200,"pipeline pump stalled: "..line)
 return p.exit_code
end
''')
lua.execute(r'''
sink.data=""
assert(run_line("cat /in.txt | grep alp | head -n 2")==0)
assert(sink.data=="alpha\nalpine\n","pipeline output mismatch: "..sink.data)

sink.data=""
assert(run_line("cat < /in.txt | wc > /count.txt")==0)
assert(files["/count.txt"]=="5 5 31\n","redirect output mismatch: "..tostring(files["/count.txt"]))
''')
lua.execute(r'''
assert(run_line("head -n 1 /in.txt > /append.txt")==0)
assert(run_line("head -n 1 /in.txt >> /append.txt")==0)
assert(files["/append.txt"]=="alpha\nalpha\n","append redirect mismatch")

local parsed=assert(pipeline.parse([[cat "a b" | grep 'a b' >> out.txt]]))
assert(#parsed==2)
assert(parsed[1].argv[2]=="a b")
assert(parsed[2].argv[2]=="a b")
assert(parsed[2].stdout=="out.txt" and parsed[2].append==true)
''')
print("PIPELINE_RUNTIME_OK")
print("PIPE_DATAFLOW_PASS")
print("PIPE_INPUT_REDIRECT_PASS")
print("PIPE_OUTPUT_APPEND_PASS")
print("PIPE_QUOTED_PARSE_PASS")

lua.execute(r'''
assert(run_line("cat /missing.txt 2> /err.txt")==1)
assert(files["/err.txt"]:find("cat:",1,true),"stderr redirect missing")

local fdproc=assert(kernel.process.create{
 name="fdtest",uid=1000,gid=1000,cwd="/",environment={},capabilities={},
 stdout=sink,stderr=sink,fd={[1]=sink,[2]=sink}
})
assert(kernel.syscalls.dup(fdproc,1,9)==9)
assert(kernel.syscalls.getfd(fdproc,9)==sink)
assert(kernel.syscalls.close(fdproc,9)==true)
local _,fdErr=kernel.syscalls.getfd(fdproc,9)
assert(fdErr=="EBADF")
''')
print("PIPE_STDERR_REDIRECT_PASS")
print("FD_DUP_CLOSE_PASS")
