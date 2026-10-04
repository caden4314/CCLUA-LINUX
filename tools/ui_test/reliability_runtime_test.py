from pathlib import Path
from lupa import LuaRuntime

ROOT=Path(r"E:\Minecraft\CCLUA-LINUX")
lua=LuaRuntime(unpack_returned_tuples=True)
g=lua.globals()

g.py_read=lambda p:(ROOT/"src"/str(p).lstrip("/").replace("/", "\\")).read_text(encoding="utf-8")

lua.execute(r'''
os=os or {}
function os.epoch(_) return 1000000 end
function os.getComputerID() return 22 end
function os.queueEvent(...) end

colors={
  white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,gray=128,
  lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,green=8192,red=16384,black=32768
}

term={}
function term.setBackgroundColor(_) end
function term.setTextColor(_) end
function term.clear() end
function term.clearLine() end
function term.setCursorPos(x,y) end
function term.getCursorPos() return 1,1 end
function term.getSize() return 102,38 end
function term.write(_) end
write=function(_) end
print=function(...) end

local files={
  ["var/lib/cclua/installed-commit"]="testcommit123\n",
}
local dirs={
  ["var"]=true,["var/lib"]=true,["var/lib/cclua"]=true,
  ["System/kernel/init.lua"]=false,
}
local always_exists={
  ["System/kernel/init.lua"]=true,
  ["System/kernel/scheduler.lua"]=true,
  ["System/init/init.lua"]=true,
  ["usr/lib/cclua/config.lua"]=true,
  ["usr/lib/cclua/service_manager.lua"]=true,
  ["usr/lib/cclua/services/netd.lua"]=true,
  ["usr/bin/cclua-desktop.lua"]=true,
  ["usr/lib/cclua/desktop/compositor.lua"]=true,
  ["usr/lib/cclua/desktop/apps/terminal.lua"]=true,
}

fs={}
function fs.exists(p)
  p=tostring(p):gsub("^/","")
  return files[p]~=nil or dirs[p]==true or always_exists[p]==true
end
function fs.isDir(p) p=tostring(p):gsub("^/",""); return dirs[p]==true end
function fs.makeDir(p) dirs[tostring(p):gsub("^/","")]=true end
function fs.getDir(p) p=tostring(p):gsub("\\","/"); return p:match("^(.*)/[^/]+$") or "" end
function fs.getFreeSpace(_) return 1024*1024 end
function fs.delete(p) files[tostring(p):gsub("^/","")]=nil end
function fs.open(p,mode)
  p=tostring(p):gsub("^/","")
  if mode=="w" then
    local buf=""
    return {
      write=function(s) buf=buf..tostring(s or "") end,
      writeLine=function(s) buf=buf..tostring(s or "").."\n" end,
      close=function() files[p]=buf end
    }
  elseif mode=="a" then
    local buf=files[p] or ""
    return {
      write=function(s) buf=buf..tostring(s or "") end,
      writeLine=function(s) buf=buf..tostring(s or "").."\n" end,
      close=function() files[p]=buf end
    }
  elseif mode=="r" and files[p]~=nil then
    local value=files[p]
    return {readAll=function() return value end,close=function() end}
  end
  return nil
end

textutils={}
function textutils.serializeJSON(_) return "{}" end
function textutils.unserializeJSON(_) return {} end

peripheral={}
function peripheral.getNames() return {"top"} end
function peripheral.hasType(name,kind) return name=="top" and kind=="modem" end
function peripheral.getType(_) return "modem" end
function peripheral.wrap(name)
  if name=="top" then return {isWireless=function() return true end} end
end
function peripheral.find(_,_) return nil end

local machine={hostname="test-client",role="desktop-client",image="ubuntu-22.04-desktop",manager_computer_id=0}
local config={}
function config.machine() return machine end
function config.read_json(path,default) return default or {} end
function config.write_json(path,data) files[tostring(path):gsub("^/","")]="{}"; return true end

function dofile(path)
  if path=="/usr/lib/cclua/config.lua" then return config end
  local code=py_read(path)
  local fn,err=load(code,"@"..path,"t",_G)
  if not fn then error(err) end
  return fn()
end

kernel={
  version={version="0.test",kernel_abi=1},
  process={},scheduler={},services={},vfs={},device={},users={},log={}
}
function kernel.device.scan(_) return {top={type="modem"}} end
function kernel.device.snapshot() end
function kernel.users.by_name(name) if name=="caden" then return {name="caden"} end end
function kernel.scheduler.sleep(_) end
function kernel.log.write(...) end
ctx={kernel=kernel,process={pid=1}}
''')

# POST happy-path desktop: no external monitor is valid, all critical checks pass.
lua.execute(r'''
post=dofile("/usr/lib/cclua/post.lua")
result=post.run(ctx,{animate=false,monitors=false})
assert(result.fatal==false)
assert(result.state=="PASSED",result.state)
assert(result.fail==0)
''')

# Service supervisor: transient failures recover; burst failures stop.
lua.execute(r'''
local serviceManager=dofile("/usr/lib/cclua/service_manager.lua")

local pid=1
local procs={}
local sleeps={}
local logs={}
local k={
  capabilities={root=function() return {} end},
  log={write=function(...) table.insert(logs,{...}) end},
  process={},
  scheduler={},
}
function k.process.create(spec)
  pid=pid+1
  local p={pid=pid,state="new",name=spec.name}
  procs[p.pid]=p
  return p
end
function k.process.get(id) return procs[id] end
function k.process.exit(p,code,state) p.state=state or "exited";p.exit_code=code end
function k.scheduler.add(self,p,fn) p.worker=fn;p.state="runnable";return p end
function k.scheduler.sleep(sec) table.insert(sleeps,sec) end

local sm=serviceManager.new(k)
local calls=0
sm:register{
  name="transient.service",enabled=true,restart_burst=5,
  exec=function()
    calls=calls+1
    if calls<3 then error("temporary",0) end
    return 0
  end
}
local ok,pid1=sm:start("transient.service")
assert(ok)
local p1=k.process.get(pid1)
local wok,wres=pcall(p1.worker)
assert(wok and wres==0)
local u=sm:get("transient.service")
assert(calls==3)
assert(u.total_restarts==2)
assert(u.state=="inactive")
assert(#sleeps==2)

local badcalls=0
sm:register{
  name="broken.service",enabled=true,restart_burst=2,
  restart_delay=0,
  exec=function() badcalls=badcalls+1; error("permanent",0) end
}
local ok2,pid2=sm:start("broken.service")
assert(ok2)
local p2=k.process.get(pid2)
local bok=pcall(p2.worker)
assert(bok==false)
local bad=sm:get("broken.service")
assert(bad.state=="failed")
assert(badcalls==3)
assert(bad.total_restarts==3)
''')

# Net packet IDs, modem open verification, and duplicate rejection.
lua.execute(r'''
local configNet={machine=function() return {hostname="test-client",role="desktop-client",address="10.27.0.22"} end}
local oldDofile=dofile
function dofile(path)
  if path=="/usr/lib/cclua/config.lua" then return configNet end
  return oldDofile(path)
end
peripheral={}
function peripheral.getNames() return {"top"} end
function peripheral.hasType(name,kind) return name=="top" and kind=="modem" end
function peripheral.wrap(_) return {isWireless=function() return true end} end
rednet={opened={}}
function rednet.open(name) rednet.opened[name]=true end
function rednet.isOpen(name) return rednet.opened[name]==true end
function rednet.send(...) return true end
function rednet.broadcast(...) return true end

local net=dofile("/usr/lib/cclua/net.lua")
local opened=net.open_management_modems()
assert(#opened==1 and opened[1]=="top")
local a=net.packet("heartbeat",{})
local b=net.packet("heartbeat",{})
assert(a.id~=b.id)
local first=net.accept(0,{
  version=2,protocol=net.protocol,id="0-1-000001",sequence=1,
  kind="heartbeat",src_id=0,src="10.27.0.1",hostname="manager",role="manager",time=1,payload={}
})
assert(first~=nil)
local duplicate=net.accept(0,{
  version=2,protocol=net.protocol,id="0-1-000001",sequence=1,
  kind="heartbeat",src_id=0,src="10.27.0.1",hostname="manager",role="manager",time=1,payload={}
})
assert(duplicate==nil)
assert(net.stats.duplicates==1)

-- Wireless exists but cannot be opened: wired must become the fallback.
peripheral={}
function peripheral.getNames() return {"wireless","wired"} end
function peripheral.hasType(_,kind) return kind=="modem" end
function peripheral.wrap(name)
  return {isWireless=function() return name=="wireless" end}
end
rednet.opened={}
function rednet.open(name)
  if name=="wired" then rednet.opened[name]=true end
end
function rednet.isOpen(name) return rednet.opened[name]==true end
local fallback=net.open_management_modems()
assert(#fallback==1 and fallback[1]=="wired")
''')

print("RELIABILITY_RUNTIME_OK")
print("POST_PASS")
print("SERVICE_RECOVERY_PASS")
print("NETWORK_PACKET_PASS")
print("MODEM_FALLBACK_PASS")
