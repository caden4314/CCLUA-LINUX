from pathlib import Path
from lupa import LuaRuntime

ROOT = Path(r"E:\Minecraft\CCLUA-LINUX")
lua = LuaRuntime(unpack_returned_tuples=True)
g = lua.globals()

def read_repo(path):
    p = ROOT / "src" / str(path).lstrip("/").replace("/", "\\")
    return p.read_text(encoding="utf-8")

g.py_read = read_repo

lua.execute(r'''
colors={
  white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
  gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
  green=8192,red=16384,black=32768
}

output={}
pending=""
function write(s) pending=pending..tostring(s or "") end
function print(...)
  local parts={}
  for i=1,select("#",...) do parts[#parts+1]=tostring(select(i,...)) end
  output[#output+1]=pending..table.concat(parts,"\t")
  pending=""
end
''')

lua.execute(r'''
local termColor=colors.white
term={}
function term.setTextColor(c) termColor=c end
term.setTextColour=term.setTextColor
function term.getTextColor() return termColor end
term.getTextColour=term.getTextColor
function term.setBackgroundColor(_) end
term.setBackgroundColour=term.setBackgroundColor
function term.clear() output={};pending="" end
function term.setCursorPos(_,_) end
function term.getSize() return 102,38 end
function term.current() return term end

function reset_output() output={};pending="" end
function output_text()
  local t={}
  for i,v in ipairs(output) do t[#t+1]=v end
  if pending~="" then t[#t+1]=pending end
  return table.concat(t,"\n")
end

local nextTimer=0
os.getComputerID=function() return 4 end
os.clock=function() return 123.4 end
os.date=function(_) return "19:42:11" end
os.startTimer=function(_) nextTimer=nextTimer+1 return nextTimer end
''')

lua.execute(r'''
config={}
function config.machine()
  return {
    hostname="serverr-4",role="server-worker",address="10.27.0.24",
    manager="10.27.0.1",monitor_side="right",channel="main"
  }
end
function config.read_json(path,default)
  if path:find("status.json",1,true) then
    return {state="DEGRADED",error_code=1,error_reason="service failure",service_restarts=2}
  elseif path:find("post.json",1,true) then
    return {state="PASSED",pass=11,warn=0,fail=0,fatal=false,degraded=false}
  elseif path:find("network-health.json",1,true) then
    return {state="ONLINE",manager_rtt_ms=3,missed_probes=0,modem_count=1,reopen_count=0}
  elseif path:find("session-health.json",1,true) then
    return {mode="console",recovery=false}
  elseif path:find("update-state.json",1,true) then
    return {state="CURRENT",percent=100,current_commit="abcdef0123456789",
      available_commit="abcdef0123456789",auto_apply=true,manager_state="CURRENT"}
  elseif path:find("network.json",1,true) then
    return {peers={{id=0},{id=22}},stats={rx=120,tx=98,duplicates=0}}
  end
  return default or {}
end
''')

lua.execute(r'''
local units={
  {name="systemd-networkd.service",description="Network service",state="active",
    enabled=true,pid=8,total_restarts=0},
  {name="cclua-statusd.service",description="Health service",state="active",
    enabled=true,pid=3,total_restarts=0},
  {name="example-failed.service",description="Example failure",state="failed",
    enabled=true,pid=nil,total_restarts=2,error="simulated service failure"},
}
services={units=units}
function services:list() return self.units end
function services:get(name)
  for _,u in ipairs(self.units) do if u.name==name then return u end end
end
function services:start(name) return self:get(name)~=nil,"not found" end
function services:stop(name) return self:get(name)~=nil,"not found" end
function services:restart(name) return self:get(name)~=nil,"not found" end
function services:enable(name) return self:get(name)~=nil,"not found" end
function services:disable(name) return self:get(name)~=nil,"not found" end

processes={
  {pid=1,uid=0,state="running",name="init"},
  {pid=3,uid=0,state="running",name="cclua-statusd.service"},
  {pid=8,uid=0,state="waiting",name="systemd-networkd.service"},
}
''')

lua.execute(r'''
ctx={
  process={pid=40,uid=0,gid=0,groups={},cwd="/root",environment={}},
  unit={details={}},
}
ctx.kernel={
  version={version="0.2.0-dev",kernel_abi=1},
  services=services,
  process={all=function() return processes end},
  users={by_uid=function(uid) return {name=uid==0 and "root" or "caden",home=uid==0 and "/root" or "/home/caden"} end},
  device={devices={right={type="monitor"},top={type="modem"}}},
  log={write=function(...) end},
  exec={resolve=function(_) return nil end,load=function(_) return nil end},
  vfs={normalize=function(p) return p end,exists=function(_) return true end,isDir=function(_) return true end},
  scheduler={add=function(...) end},
}

monitor={w=79,h=38,x=1,y=1,lines={}}
function monitor.getSize() return monitor.w,monitor.h end
function monitor.setCursorPos(x,y) monitor.x=x;monitor.y=y end
function monitor.setTextColor(_) end
function monitor.setBackgroundColor(_) end
function monitor.clear() monitor.lines={} end
function monitor.write(s)
  local old=monitor.lines[monitor.y] or ""
  if #old<monitor.x-1 then old=old..string.rep(" ",monitor.x-1-#old) end
  local tail=old:sub(monitor.x+#s)
  monitor.lines[monitor.y]=old:sub(1,monitor.x-1)..tostring(s)..tail
end
''')

lua.execute(r'''
peripheral={}
function peripheral.getType(name) if name=="right" then return "monitor" end end
function peripheral.wrap(name) if name=="right" then return monitor end end
function peripheral.find(kind,fn)
  if kind=="monitor" and (not fn or fn("right",monitor)) then return monitor end
end

monitorLayout={}
function monitorLayout.configure(mon,machine,opts)
  return {scale=1,width=79,height=38,fits=true}
end

function dofile(path)
  if path=="/usr/lib/cclua/config.lua" then return config end
  if path=="/usr/lib/cclua/monitor_layout.lua" then return monitorLayout end
  local code=py_read(path)
  local fn,err=load(code,"@"..path,"t",_G)
  if not fn then error(err) end
  return fn()
end

function monitor_text()
  local out={}
  for y=1,monitor.h do out[#out+1]=monitor.lines[y] or "" end
  return table.concat(out,"\n")
end
''')

lua.execute(r'''
reset_output()
local status=dofile("/usr/bin/cclua-status.lua")
status_rc=status.main(ctx,{})
status_out=output_text()

reset_output()
local systemctl=dofile("/usr/bin/systemctl.lua")
systemctl_rc=systemctl.main(ctx,{"status","example-failed.service"})
systemctl_out=output_text()

reset_output()
local top=dofile("/usr/bin/top.lua")
top_rc=top.main(ctx,{"--batch"})
top_out=output_text()

reset_output()
local cclua=dofile("/usr/bin/cclua.lua")
cclua_rc=cclua.main(ctx,{"status"})
cclua_out=output_text()

reset_output()
cclua_services_rc=cclua.main(ctx,{"services","failed"})
cclua_services_out=output_text()

reset_output()
local fastfetch=dofile("/usr/bin/fastfetch.lua")
fastfetch_rc=fastfetch.main(ctx,{"--plain"})
fastfetch_out=output_text()

reset_output()
read=function(_,_) return nil end
local shell=dofile("/usr/lib/cclua/shell.lua")
shell_rc=shell.run(ctx,{"--login"})
shell_out=output_text()

local dash=dofile("/usr/lib/cclua/services/dashboard.lua")
local co=coroutine.create(function() return dash(ctx) end)
assert(coroutine.resume(co))
assert(coroutine.resume(co,"timer",1))
dashboard_out=monitor_text()
''')

def check(name, text, terms):
    missing=[term for term in terms if term not in text]
    if missing:
        raise AssertionError(f"{name} missing {missing}\n{text}")

status_out=str(g.status_out)
systemctl_out=str(g.systemctl_out)
top_out=str(g.top_out)
cclua_out=str(g.cclua_out)
cclua_services_out=str(g.cclua_services_out)
fastfetch_out=str(g.fastfetch_out)
shell_out=str(g.shell_out)
dashboard_out=str(g.dashboard_out)

assert int(g.status_rc)==1
check("cclua-status",status_out,["CCLUA system status","System","Network","Updates","Attention","example-failed.service"])
assert int(g.systemctl_rc)==3
check("systemctl",systemctl_out,["example-failed.service","Active:","Error:","Hint:"])
assert int(g.top_rc)==0
check("top",top_out,["Tasks:","Services:","PID USER","systemd-networkd.service"])
assert int(g.cclua_rc)==1
check("cclua status",cclua_out,["serverr-4","System","Services","Network","Update"])
assert int(g.cclua_services_rc)==1
check("cclua services",cclua_services_out,["SERVICES","example-failed.service","simulated service failure"])
assert int(g.fastfetch_rc)==1
check("fastfetch",fastfetch_out,["Ubuntu 22.04.5 / CCLUA","caden@serverr-4","Kernel:","Network:","Update:"])
assert int(g.shell_rc)==0
check("shell",shell_out,["Ubuntu 22.04.5 LTS [CCLUA]","SYSTEM DEGRADED","NET ONLINE","POST PASSED"])
check("dashboard",dashboard_out,["SYSTEM","NETWORK","UPDATE","SERVICES","example-failed.service"])

print("SERVER_UI_RUNTIME_OK")
print("STATUS_HIERARCHY_PASS")
print("SYSTEMCTL_ERROR_UX_PASS")
print("TOP_TABLE_PASS")
print("SYSTEM_API_UNIFIED_CLI_PASS")
print("FASTFETCH_PASS")
print("SHELL_MOTD_PASS")
print("WIDE_DASHBOARD_PASS")
