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
last_refresh_timer=nil
os.epoch=function(_) return mock_now end
os.startTimer=function(delay)
  mock_timer=mock_timer+1
  if tonumber(delay)==0.25 then last_refresh_timer=mock_timer end
  return mock_timer
end
os.queueEvent=function(...) end

saved_state={}
mock_machine={
  role="theater-controller",theater_enabled=true,
  theater_bridge_base="http://127.0.0.1:8766/v1",
  theater_main_monitor="monitor_7",
  theater_transport_monitor="left",
  theater_control_monitor="right",
  theater_booth_speaker="bottom",
  theater_video_fps=20,theater_video_cols=0,theater_video_rows=0,
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
  if raw=="CATALOG" then
    return {movies={{
      id="movie1",title="Test Feature",duration=120,
      audio_url="/v1/movies/movie1/audio.pcm",
      video_url="/v1/movies/movie1/video.blit",
    }}}
  end
  return {}
end

http_requests={}
pending_http={}
http={}
function http.get(url,headers,binary)
  url=tostring(url)
  http_requests[#http_requests+1]=url
  if url:find("/catalog",1,true) then
    return {
      getResponseCode=function() return 200 end,
      readAll=function() return "CATALOG" end,
      close=function() end,
    }
  end
  error("synchronous media request should not be used: "..url)
end

function http.request(opts,post,headers,binary)
  local url
  if type(opts)=="table" then url=tostring(opts.url or "")
  else url=tostring(opts or "") end
  http_requests[#http_requests+1]=url
  pending_http[url]=true
  return true
end

function make_catalog_handle()
  return {
    getResponseCode=function() return 200 end,
    readAll=function() return "CATALOG" end,
    close=function() end,
  }
end

function make_error_handle(code)
  return {
    getResponseCode=function() return tonumber(code) or 500 end,
    close=function() end,
  }
end

test_palette_hex="102030"..string.rep("406080",14).."000000"
test_palette_hex_2="a0b0c0"..string.rep("806040",14).."000000"
test_palette_sequence=test_palette_hex..test_palette_hex_2
function make_segment_handle(packets)
  packets=tonumber(packets) or 2
  local frameBytes=223*73*3
  local audioBytes=2400
  local one=string.rep(" ",frameBytes)..string.rep(string.char(64),audioBytes)
  local raw=string.rep(one,packets)
  return {
    getResponseCode=function() return 200 end,
    getResponseHeaders=function()
      return {
        ["Content-Length"]=tostring(#raw),
        ["X-CCLUA-Format"]="av-segment-v1",
        ["X-CCLUA-Cols"]="223",
        ["X-CCLUA-Rows"]="73",
        ["X-CCLUA-FPS"]="20.000",
        ["X-CCLUA-Frame-Bytes"]=tostring(frameBytes),
        ["X-CCLUA-Audio-Bytes"]=tostring(audioBytes),
        ["X-CCLUA-Sample-Rate"]="48000",
        ["X-CCLUA-Packets"]=tostring(packets),
        ["X-CCLUA-Palette-RGB-Sequence"]=test_palette_sequence,
        ["X-CCLUA-Palette-Count"]="2",
        ["X-CCLUA-Palette-Frames"]=tostring(math.max(1,math.ceil(packets/2))),
        ["X-CCLUA-Color-Mode"]="adaptive16x4-fs",
      }
    end,
    readAll=function() return raw end,
    close=function() end,
  }
end

relay_state={}
objects={}
types={}

local function monitor(w,h,initialScale)
  initialScale=tonumber(initialScale) or 1
  local m={baseW=w*initialScale,baseH=h*initialScale,scale=initialScale,palette={},paletteWrites=0}
  for i=0,15 do m.palette[i+1]={0.1+i/100,0.2+i/100,0.3+i/100} end
  local function paletteIndex(color)
    for i=0,15 do if color==2^i then return i+1 end end
    return 1
  end
  function m.getSize()
    return math.floor(m.baseW/m.scale+0.5),math.floor(m.baseH/m.scale+0.5)
  end
  function m.setTextScale(s) m.scale=s end
  function m.getTextScale() return m.scale end
  function m.getPaletteColor(color)
    local rgb=m.palette[paletteIndex(color)]
    return rgb[1],rgb[2],rgb[3]
  end
  function m.setPaletteColor(color,r,g,b)
    m.palette[paletteIndex(color)]={r,g,b}
    m.paletteWrites=m.paletteWrites+1
  end
  function m.setCursorBlink(_) end
  function m.setBackgroundColor(_) end
  function m.setTextColor(_) end
  function m.clear() end
  function m.setCursorPos(_,_) end
  function m.write(_) end
  function m.blit(_,_,_) end
  return m
end

objects["monitor_7"]=monitor(167,55,2.0); types["monitor_7"]="monitor"
objects["left"]=monitor(57,24,1.0); types["left"]="monitor"
objects["right"]=monitor(72,48,1.0); types["right"]="monitor"

speaker_calls={}
for id=0,21 do
  local name="speaker_"..id
  local s={}
  function s.playAudio(audio,volume)
    speaker_calls[#speaker_calls+1]={name=name,volume=volume,first=audio[1],samples=#audio}
    return true
  end
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
  function r.getOutput(side) assert(side=="bottom");return relay_state[id] end
  function r.setOutput(side,value) assert(side=="bottom");relay_state[id]=value==true end
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

processes={}
next_pid=100
child_order={}

local process_api={}
function process_api.get(pid) return processes[pid] end
function process_api.create(spec)
  next_pid=next_pid+1
  local p={
    pid=next_pid,ppid=spec.ppid,name=spec.name,
    uid=spec.uid,gid=spec.gid,groups=spec.groups,cwd=spec.cwd,
    capabilities=spec.capabilities,argv=spec.argv,
    state="created",cpu_resumes=0,
  }
  processes[p.pid]=p
  child_order[#child_order+1]=p.pid
  return p
end
function process_api.exit(p,code,state)
  p.state=state or "exited";p.exit_code=code or 0
end

local scheduler_api={}
function scheduler_api:add(p,fn)
  p.coroutine=coroutine.create(fn)
  p.state="runnable"
  return p
end

ctx={
  process={pid=50,uid=0,gid=0,groups={},cwd="/",capabilities={}},
  unit={},
  kernel={
    log={write=function(...) end},
    process=process_api,
    scheduler=scheduler_api,
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

function run_children_once()
  for _,pid in ipairs(child_order) do
    local p=processes[pid]
    if p and p.coroutine and p.state~="exited" and p.state~="killed" and p.state~="crashed" then
      if p.state=="sleeping" and (p.wake_at or math.huge)<=mock_now then p.state="runnable" end
      if p.state=="runnable" then
        p.cpu_resumes=p.cpu_resumes+1
        local ok,req,arg=coroutine.resume(p.coroutine)
        assert(ok,tostring(req))
        if coroutine.status(p.coroutine)=="dead" then
          p.state="exited";p.exit_code=tonumber(req) or 0
        elseif req=="sleep" then
          p.state="sleeping";p.wake_at=tonumber(arg) or mock_now
        elseif req=="wait_event" then
          p.state="waiting";p.event_filter=arg
        else
          p.state="runnable"
        end
      end
    end
  end
end

function count_lights()
  local n=0
  for _,v in pairs(relay_state) do if v then n=n+1 end end
  return n
end

function assert_lit_exact(expected,label)
  local wanted={}
  for _,id in ipairs(expected) do wanted[id]=true end
  for id,v in pairs(relay_state) do
    assert(v==(wanted[id]==true),
      ("%s relay %d expected %s got %s"):format(label,id,tostring(wanted[id]==true),tostring(v)))
  end
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
local catalogUrl=nil
for i=#http_requests,1,-1 do
  if http_requests[i]:find("/catalog",1,true) then catalogUrl=http_requests[i];break end
end
assert(catalogUrl,"asynchronous catalog request missing")
kind=drive("http_success",catalogUrl,make_catalog_handle(),nil)
assert(kind=="wait_event")
assert(saved_state.state=="IDLE")
assert(saved_state.hardware.relays_present==55)
assert(saved_state.hardware.speakers_present==22)
assert(saved_state.hardware.speakers_expected==22)
assert(saved_state.hardware.main_present==true)
assert(saved_state.hardware.transport_present==true)
assert(saved_state.hardware.control_present==true)
assert(saved_state.hardware.main_size[1]==223 and saved_state.hardware.main_size[2]==73,
  ("expected 223x73 theater wall, got %dx%d"):format(
    saved_state.hardware.main_size[1],saved_state.hardware.main_size[2]))
assert(saved_state.hardware.main_text_scale==1.5)
assert(saved_state.hardware.speaker_output_volume==3.0)
assert(count_lights()==55)

kind=drive("cclua_theater_command","scene",{scene="feature"})
assert(kind=="wait_event")
assert(saved_state.scene=="feature")
assert(saved_state.lighting_transition==true)
settle_brightness(9)
assert(count_lights()==5,("feature fixture count %d"):format(count_lights()))
assert_lit_exact({124,119,128,82,118},"feature")

kind=drive("cclua_theater_command","scene",{scene="trailers"})
assert(kind=="wait_event")
assert(saved_state.scene=="trailers")
assert(saved_state.lighting_transition==true)
settle_brightness(30)
assert(count_lights()==17,("trailers fixture count %d"):format(count_lights()))
assert_lit_exact({
  124,119,128,82,118,120,127,81,117,
  80,115,79,116,78,114,77,113
},"trailers")

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
assert(count_lights()==27,("50 percent fixture count %d"):format(count_lights()))

-- Playback uses finite half-second A/V segments. Requests are asynchronous:
-- the first request may fail/retry without blocking theaterd, and the next
-- segment is prefetched while the current one is playing. Master volume scales
-- PCM samples while the speaker API stays at full theater output range.
kind=drive("cclua_theater_command","volume",{value=0.5})
assert(kind=="wait_event")
kind=drive("cclua_theater_command","play",{id="movie1"})
assert(kind=="wait_event")
assert(saved_state.state=="BUFFERING")
assert(#child_order==2,"expected segmented player plus audio pump")
assert(processes[child_order[1]].name=="cclua-theater-segment-player","first theater child should be segment player")
assert(processes[child_order[2]].name=="cclua-theater-audio-pump","second theater child should be audio pump")

local function latest_segment_url(seq)
  local needle="seq="..tostring(seq)
  for i=#http_requests,1,-1 do
    local url=http_requests[i]
    if url:find("/av.segment",1,true) and url:find(needle,1,true) then return url end
  end
end

local firstUrl=latest_segment_url(0)
assert(firstUrl,"segment 0 request missing")
assert(firstUrl:find("seconds=1.000",1,true))
assert(firstUrl:find("cols=223",1,true))
assert(firstUrl:find("rows=73",1,true))
assert(firstUrl:find("fps=20.000",1,true))
assert(firstUrl:find("color=adaptive16x4",1,true))

run_children_once()
assert(processes[child_order[1]].state=="sleeping","player should wait for first segment")

kind=drive("http_failure",firstUrl,"Could not connect",nil)
assert(kind=="wait_event")
local retryUrl=latest_segment_url(0)
assert(retryUrl~=firstUrl,"segment 0 retry URL should carry a new attempt id")
assert(retryUrl:find("attempt=1",1,true),"segment 0 retry attempt id missing")

kind=drive("http_success",retryUrl,make_segment_handle(4),nil)
assert(kind=="wait_event")
run_children_once()
local secondUrl=latest_segment_url(1)
assert(secondUrl,"segment 1 was not prefetched")

mock_now=mock_now+20
run_children_once()
assert(processes[child_order[1]].state=="sleeping","player should wait for startup prebuffer")
assert(#speaker_calls==0,"audio started before the four-segment buffer was ready")

for seq=1,5 do
  local url=latest_segment_url(seq)
  assert(url,("startup segment %d was not prefetched"):format(seq))
  kind=drive("http_success",url,make_segment_handle(4),nil)
  assert(kind=="wait_event")
  run_children_once()
  if seq<5 then
    mock_now=mock_now+20
    run_children_once()
    if seq<3 then
      assert(#speaker_calls==0,
        ("audio started before startup segment %d/5 completed"):format(seq))
    else
      assert(#speaker_calls==66,
        ("expected three 22-speaker calibration tones after startup prebuffer, got %d"):format(#speaker_calls))
    end
  end
end

local seventhUrl=latest_segment_url(6)
assert(seventhUrl,"segment 6 was not prefetched after startup buffer")

mock_now=mock_now+20
run_children_once()
assert(processes[child_order[1]].state=="sleeping","player should wait for synchronized start")

mock_now=mock_now+300
run_children_once()
mock_now=mock_now+125
for _=1,3 do run_children_once() end

local moviePalette=objects["monitor_7"].palette[1]
assert(math.abs(moviePalette[1]-(0x10/255))<0.001)
assert(math.abs(moviePalette[2]-(0x20/255))<0.001)
assert(math.abs(moviePalette[3]-(0x30/255))<0.001)

assert(#speaker_calls==154,("expected 66 calibration + four 22-speaker prebuffer epochs, got %d"):format(#speaker_calls))
local expected_first={"speaker_7","speaker_2","speaker_8","speaker_15","speaker_20","speaker_18","speaker_0","speaker_1","speaker_6","speaker_5","speaker_4","speaker_3","speaker_9","speaker_10","speaker_11","speaker_12","speaker_13","speaker_14","speaker_16","speaker_17","speaker_19","speaker_21"}
local expected_set={}
for _,name in ipairs(expected_first) do expected_set[name]=true end
for tone=0,2 do
  local seen={}
  for i=1,22 do
    local call=speaker_calls[tone*22+i]
    assert(expected_set[call.name],"unexpected calibration speaker "..tostring(call.name))
    assert(not seen[call.name],"duplicate calibration speaker "..tostring(call.name))
    seen[call.name]=true
    assert(call.volume==1.2,"calibration tone volume should be bounded")
  end
end
local feature_seen={}
for i=1,22 do
  local call=speaker_calls[66+i]
  assert(expected_set[call.name],"unexpected feature speaker "..tostring(call.name))
  assert(not feature_seen[call.name],"duplicate feature speaker "..tostring(call.name))
  feature_seen[call.name]=true
  assert(call.volume==3.0,"speaker output volume must stay at theater range")
  assert(call.first==32,("PCM master gain expected sample 32 got %s"):format(tostring(call.first)))
end

assert(last_refresh_timer~=nil)
kind=drive("timer",last_refresh_timer)
assert(kind=="wait_event")
assert(saved_state.state=="PLAYING","segmented playback did not leave BUFFERING")
assert(saved_state.streams.av.ready==true)
assert(saved_state.streams.av.cols==223)
assert(saved_state.streams.av.rows==73)
assert(saved_state.streams.av.audio_bytes==2400)
assert(saved_state.streams.av.color_mode=="adaptive16x4-fs")
assert(saved_state.streams.av.speaker_submit_ok==22)
assert(saved_state.streams.av.speaker_submit_failed==0)
assert(saved_state.streams.av.speaker_submit_total==22)
assert(saved_state.streams.av.speaker_output_volume==3.0)
assert(saved_state.streams.av.initial_buffer_segments==4)
assert(saved_state.streams.av.prefetch_segments==6)
assert(saved_state.streams.av.inflight_index==6)
assert(saved_state.streams.av.buffered_segments>=5,
  "startup playback cushion was not retained")

kind=drive("http_success",seventhUrl,make_segment_handle(4),nil)
assert(kind=="wait_event")
run_children_once()
kind=drive("timer",last_refresh_timer)
assert(kind=="wait_event")
assert(saved_state.streams.av.buffered_segments>=6,
  "deep playback cushion was not retained")

local segmentRequests=0
for _,url in ipairs(http_requests) do
  if url:find("/av.segment",1,true) then segmentRequests=segmentRequests+1 end
  assert(not url:find("/av.stream",1,true),"open-ended A/V stream must not be used")
  assert(not url:find("/audio.pcm",1,true),"normal playback used split audio endpoint")
  assert(not url:find("/video.blit",1,true),"normal playback used split video endpoint")
end
assert(segmentRequests>=4,"segment retry/prefetch did not issue expected requests")

kind=drive("cclua_theater_command","pause",{})
assert(kind=="wait_event")
local restored=objects["monitor_7"].palette[1]
assert(math.abs(restored[1]-0.1)<0.001)
assert(math.abs(restored[2]-0.2)<0.001)
assert(math.abs(restored[3]-0.3)<0.001)

-- CC:Tweaked delivers bridge HTTP 416 as http_failure. It is an EOF signal,
-- not a playback error.
kind=drive("cclua_theater_command","play",{id="movie1"})
assert(kind=="wait_event")
local eofUrl=latest_segment_url(0)
assert(eofUrl,"EOF test segment request missing")
kind=drive("http_failure",eofUrl,"Requested Range Not Satisfiable",make_error_handle(416))
assert(kind=="wait_event")
kind=drive("timer",last_refresh_timer)
assert(kind=="wait_event")
assert(saved_state.state~="ERROR","HTTP 416 EOF incorrectly changed playback to error")
assert(saved_state.error==nil,"HTTP 416 EOF left an error in theater state")

print("THEATER_RUNTIME_OK")
print("MONITORS_3_OF_3_PASS")
print("SPEAKERS_22_OF_22_PASS")
print("RELAYS_55_OF_55_PASS")
print("FEATURE_5_GUIDE_FIXTURES_PASS")
print("TRAILERS_17_SYMMETRIC_FIXTURES_PASS")
print("PRESHOW_33_FIXTURES_PASS")
print("DIMMER_50_PERCENT_27_SYMMETRIC_FIXTURES_PASS")
print("ASYNC_SEGMENT_PREBUFFER_PASS")
print("SEGMENT_RETRY_AND_PREFETCH_PASS")
print("FULL_WALL_223X73_20FPS_SEGMENT_REQUEST_PASS")
print("ADAPTIVE_4X24BIT_PALETTE_PASS")
print("MASTER_PCM_GAIN_AND_22_SPEAKER_SUBMIT_PASS")
print("MOVIE_PALETTE_RESTORE_PASS")
''')
