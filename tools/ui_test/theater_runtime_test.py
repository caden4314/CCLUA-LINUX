from pathlib import Path
from lupa import LuaRuntime

ROOT=Path(r"E:\Minecraft\CCLUA-LINUX")
lua=LuaRuntime(unpack_returned_tuples=True)
g=lua.globals()
g.py_read=lambda p:(ROOT/"src"/str(p).lstrip("/").replace("/","\\")).read_text(encoding="utf-8")

lua.execute(r'''
colors={white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
 gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
 green=8192,red=16384,black=32768}

mock_now=1000000
mock_timer=0
os.epoch=function(_) return mock_now end
os.startTimer=function(_) mock_timer=mock_timer+1 return mock_timer end
os.queueEvent=function(...) end

saved_state={}
mock_machine={
  role="theater-controller",theater_enabled=true,
  theater_bridge_base="http://127.0.0.1:8766/v1",
  theater_main_monitor="monitor_7",
  theater_transport_monitor="north",
  theater_control_monitor="south",
  theater_booth_speaker="bottom",
  theater_video_fps=12,theater_video_cols=144,theater_video_rows=54,
}
mock_config={
  machine=function() return mock_machine end,
  read_json=function(path,default)
    if path=="/var/lib/cclua/theater-state.json" then return saved_state end
    return default
  end,
  write_json=function(path,value)
    if path=="/var/lib/cclua/theater-state.json" then saved_state=value end
    return true
  end,
}
mock_layout={
  fit=function(mon,opts)
    if opts and opts.fixed_scale then mon.setTextScale(opts.fixed_scale) end
    local w,h=mon.getSize()
    return opts and opts.fixed_scale or 1,w,h,true
  end
}

textutils={}
function textutils.unserializeJSON(raw)
  if raw=="CATALOG" then return {movies={}} end
  return {}
end

http={}
function http.get(url,headers,binary)
  if tostring(url):find("/catalog",1,true) then
    return {
      getResponseCode=function() return 200 end,
      readAll=function() return "CATALOG" end,
      close=function() end,
    }
  end
  return nil,"unexpected URL in theater runtime test"
end

relay_state={}
objects={}
types={}

local function monitor(w,h)
  local m={w=w,h=h,scale=1}
  function m.getSize() return m.w,m.h end
  function m.setTextScale(s) m.scale=s end
  function m.getTextScale() return m.scale end
  function m.setCursorBlink(_) end
  function m.setBackgroundColor(_) end
  function m.setTextColor(_) end
  function m.clear() end
  function m.setCursorPos(_,_) end
  function m.write(_) end
  function m.blit(_,_,_) end
  return m
end

objects["monitor_7"]=monitor(167,55); types["monitor_7"]="monitor"
objects["north"]=monitor(72,38); types["north"]="monitor"
objects["south"]=monitor(104,38); types["south"]="monitor"

for id=0,21 do
  local name="speaker_"..id
  local s={}
  function s.playAudio(_,_) return true end
  function s.stop() end
  objects[name]=s;types[name]="speaker"
end
objects["bottom"]={playAudio=function(_,_) return true end,stop=function() end}
types["bottom"]="speaker"

local relay_ids={
  74,75,76,77,78,79,80,81,82,120,119,
  91,90,89,88,87,86,85,84,83,121,122,
  92,93,94,95,96,97,98,99,100,123,124,
  109,108,107,106,105,104,103,102,101,125,126,
  110,111,112,113,114,116,115,117,118,127,128,
}
for _,id in ipairs(relay_ids) do
  local name="redstone_relay_"..id
  relay_state[id]=true
  local r={}
  function r.getOutput(side) assert(side=="down");return relay_state[id] end
  function r.setOutput(side,value) assert(side=="down");relay_state[id]=value==true end
  objects[name]=r;types[name]="redstone_relay"
end

peripheral={}
function peripheral.hasType(name,t) return types[name]==t end
function peripheral.wrap(name) return objects[name] end
function peripheral.getNames()
  local out={}
  for name in pairs(objects) do out[#out+1]=name end
  return out
end

function dofile(path)
  if path=="/usr/lib/cclua/config.lua" then return mock_config end
  if path=="/usr/lib/cclua/monitor_layout.lua" then return mock_layout end
  local code=py_read(path)
  local fn,err=load(code,"@"..path,"t",_G)
  if not fn then error(err) end
  return fn()
end

ctx={
  process={pid=50,uid=0,gid=0,groups={},cwd="/",capabilities={}},
  unit={},
  kernel={
    log={write=function(...) end},
    process={get=function(_) return nil end,exit=function(...) end,create=function(_) return nil,"not used" end},
    scheduler={add=function(...) end},
  },
}

service=dofile("/usr/lib/cclua/services/theaterd.lua")
co=coroutine.create(function() return service(ctx) end)

function drive(ev,a,b,c)
  local ok,kind,value=coroutine.resume(co,ev,a,b,c)
  assert(ok,tostring(kind))
  while kind=="sleep" do
    mock_now=tonumber(value) or (mock_now+50)
    ok,kind,value=coroutine.resume(co)
    assert(ok,tostring(kind))
  end
  return kind,value
end

function count_lights()
  local n=0
  for _,v in pairs(relay_state) do if v then n=n+1 end end
  return n
end

function settle_brightness(target)
  for _=1,40 do
    if saved_state.brightness==target and saved_state.lighting_transition~=true then return end
    drive("timer",mock_timer)
  end
  error("lighting animation did not settle at "..tostring(target))
end

local kind=drive()
assert(kind=="wait_event","service did not enter event loop")
assert(saved_state.state=="IDLE")
assert(saved_state.hardware.relays_present==55)
assert(saved_state.hardware.speakers_present==22)
assert(saved_state.hardware.main_present==true)
assert(saved_state.hardware.transport_present==true)
assert(saved_state.hardware.control_present==true)
assert(count_lights()==55)

kind=drive("cclua_theater_command","scene",{scene="feature"})
assert(kind=="wait_event")
assert(saved_state.scene=="feature")
assert(saved_state.lighting_transition==true)
settle_brightness(9)
assert(count_lights()==5,("feature fixture count %d"):format(count_lights()))

kind=drive("cclua_theater_command","scene",{scene="preshow"})
assert(kind=="wait_event")
assert(saved_state.scene=="preshow")
assert(saved_state.lighting_transition==true)
settle_brightness(60)
assert(count_lights()==33,("preshow fixture count %d"):format(count_lights()))

kind=drive("cclua_theater_command","brightness",{value=50})
assert(kind=="wait_event")
assert(saved_state.scene=="custom")
assert(saved_state.lighting_transition==true)
settle_brightness(50)
assert(count_lights()==28,("50 percent fixture count %d"):format(count_lights()))

print("THEATER_RUNTIME_OK")
print("MONITORS_3_OF_3_PASS")
print("SPEAKERS_22_OF_22_PASS")
print("RELAYS_55_OF_55_PASS")
print("FEATURE_5_FIXTURES_PASS")
print("PRESHOW_33_FIXTURES_PASS")
print("DIMMER_50_PERCENT_28_FIXTURES_PASS")
''')
