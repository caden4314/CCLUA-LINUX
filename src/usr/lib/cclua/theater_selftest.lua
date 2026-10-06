local config=dofile("/usr/lib/cclua/config.lua")
local theaterAudio=dofile("/usr/lib/cclua/services/theater_audio.lua")
local M={}

local function now() return os.epoch and os.epoch("utc") or 0 end
local function result(id,state,detail,data)
  return {id=id,state=state,detail=detail,data=data,at=now()}
end
local function speakers()
  local out={}
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name,"speaker") then
      out[#out+1]={name=name,obj=peripheral.wrap(name)}
    end
  end
  table.sort(out,function(a,b) return a.name<b.name end)
  return out
end
local function main_monitor(machine)
  local names={machine.theater_main_monitor,machine.main_monitor,"monitor_7"}
  for _,name in ipairs(names) do
    if name and peripheral.hasType(name,"monitor") then return name,peripheral.wrap(name) end
  end
  local name,obj
  obj=peripheral.find("monitor",function(n) name=n return true end)
  return name,obj
end

local function analyze_signal(samples)
  local peak,sumSq,sum,zc=0,0,0,0
  local prev=samples[1] or 0
  for i,v in ipairs(samples) do
    local a=math.abs(v);if a>peak then peak=a end
    sumSq=sumSq+v*v;sum=sum+v
    if i>1 and (v>=0)~=(prev>=0) then zc=zc+1 end
    prev=v
  end
  local n=math.max(1,#samples)
  return {peak=peak,rms=math.sqrt(sumSq/n),dc=sum/n,zero_crossings=zc}
end

local function audio_test(ctx,machine)
  local list=speakers()
  if #list~=22 then return result("audio","FAIL",("expected 22 speakers, found %d"):format(#list)) end
  local owner={active=true,audio_generation=0}
  local engine,err=theaterAudio.start(ctx,owner,list,tonumber(machine.theater_speaker_output_volume) or 3)
  if not engine then return result("audio","FAIL","engine start: "..tostring(err)) end

  local block={}
  for i=1,2400 do
    local env=math.min(1,i/120,(2401-i)/120)
    block[i]=math.floor(math.sin((i-1)*2*math.pi*880/48000)*36*env)
  end
  local epoch,queueErr=theaterAudio.enqueue(engine,block,#block)
  if not epoch then
    theaterAudio.stop(ctx,engine)
    return result("audio","FAIL","enqueue: "..tostring(queueErr))
  end

  local deadline=now()+3000
  while engine.active and engine.committed_epoch<epoch and now()<deadline do
    local ev=coroutine.yield("wait_event",{"speaker_audio_empty","timer","terminate"})
    if ev=="terminate" then break end
  end
  local st=theaterAudio.status(engine)
  theaterAudio.stop(ctx,engine)
  local signal=analyze_signal(block)
  st.signal=signal
  st.sync_model={
    same_epoch=true,same_pcm=true,samples=#block,sample_rate=48000,
    duration_ms=#block/48,maximum_submission_skew_ms=0,
  }
  st.loudness={
    digital_peak=signal.peak,digital_rms=signal.rms,
    headroom_db=signal.peak>0 and 20*math.log(127/signal.peak,10) or 99,
    note="digital loudness only; acoustic SPL requires captured client output or microphone",
  }
  if st.committed_epoch~=epoch then
    return result("audio","FAIL",("22-speaker commit timeout; pending=%d"):format(st.head_pending or -1),st)
  end
  return result("audio","PASS",
    ("22/22 synchronized PCM; RMS %.1f peak %d"):format(signal.rms,signal.peak),st)
end

local function video_test(machine)
  local name,mon=main_monitor(machine)
  if not mon then return result("video","FAIL","main theater monitor missing") end
  local ok,w,h=pcall(function() return mon.getSize() end)
  if not ok then return result("video","FAIL","monitor size query failed") end
  local rgb=type(mon.framebufferInfo)=="function" and type(mon.framebufferCreate)=="function"
    and type(mon.framebufferSubmit)=="function"
  if not rgb then
    return result("video","WARN",("%s %dx%d; RGB888 framebuffer unavailable"):format(name,w,h))
  end
  local okInfo,info=pcall(mon.framebufferInfo)
  if not okInfo or type(info)~="table" or info.format~="rgb888" then
    return result("video","FAIL","RGB888 framebuffer capability invalid")
  end

  -- Exercise the full physical wall: CCPerf maps every terminal cell to a 2x3
  -- RGB pixel tile, so 223x73 is commissioned as 446x219 native RGB pixels.
  local fw,fh=w*2,h*3
  local bytes={}
  for y=0,fh-1 do for x=0,fw-1 do
    local border=x==0 or y==0 or x==fw-1 or y==fh-1
    local cross=x==math.floor(fw/2) or y==math.floor(fh/2)
    local grid=(x%16==0) or (y%16==0)
    local r,g,b=math.floor(x*255/math.max(1,fw-1)),math.floor(y*255/math.max(1,fh-1)),0
    if border then r,g,b=255,255,255
    elseif cross then r,g,b=255,0,255
    elseif grid then r,g,b=0,255,255
    else b=((math.floor(x/8)+math.floor(y/8))%2)*96 end
    bytes[#bytes+1]=string.char(r,g,b)
  end end
  local frame=table.concat(bytes)
  local okFrame,frameErr=pcall(function()
    mon.framebufferCreate(fw,fh)
    mon.framebufferSubmit(frame)
  end)
  if not okFrame then return result("video","FAIL","full-wall RGB pixel test: "..tostring(frameErr)) end
  return result("video","PASS",("%s full-wall RGB888 %dx%d pixel/grid test (%d bytes)"):format(name,fw,fh,#frame),
    {monitor=name,cells={w,h},width=fw,height=fh,bytes=#frame,format=info.format,
     tests={"native-resolution","border","center-cross","16px-grid","gradient","checker"}})
end

function M.run(ctx,opts)
  opts=opts or {}
  local machine=config.machine()
  local started=now()
  local checks={}
  checks[#checks+1]=video_test(machine)
  checks[#checks+1]=audio_test(ctx,machine)
  local map=config.read_json("/etc/cclua/theater-speakers.json",{})
  local mapped=0
  for _,section in ipairs(map.sections or {}) do mapped=mapped+#(section.members or {}) end
  if mapped==22 then
    checks[#checks+1]=result("speaker-map","PASS","22/22 speakers assigned to physical sections",map.sections)
  else
    checks[#checks+1]=result("speaker-map","WARN",
      ("physical section map incomplete: %d/22 assigned; EQ recommendations not auto-applied"):format(mapped),
      map.sections)
  end

  local pass,warn,fail=0,0,0
  for _,r in ipairs(checks) do
    if r.state=="PASS" then pass=pass+1
    elseif r.state=="WARN" then warn=warn+1 else fail=fail+1 end
  end
  local out={
    schema=1,state=fail>0 and "FAILED" or warn>0 and "DEGRADED" or "PASSED",
    pass=pass,warn=warn,fail=fail,started_at=started,finished_at=now(),
    computer_id=os.getComputerID(),checks=checks,
  }
  config.write_json("/var/lib/cclua/theater-selftest.json",out)
  return out
end

function M.quick(machine)
  machine=machine or config.machine()
  local list=speakers()
  local name,mon=main_monitor(machine)
  local rgb=mon and type(mon.framebufferInfo)=="function"
  return {
    speakers=#list,monitor=name,monitor_present=mon~=nil,rgb888=rgb==true,
  }
end

return M
