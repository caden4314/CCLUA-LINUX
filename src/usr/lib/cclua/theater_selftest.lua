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
  if st.committed_epoch~=epoch then
    return result("audio","FAIL",("22-speaker commit timeout; pending=%d"):format(st.head_pending or -1),st)
  end
  return result("audio","PASS","22/22 accepted deterministic 48 kHz PCM epoch",st)
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

  local fw,fh=math.max(32,math.min(w*2,192)),math.max(18,math.min(h*3,108))
  local bytes={}
  for y=0,fh-1 do for x=0,fw-1 do
    bytes[#bytes+1]=string.char(
      math.floor(x*255/math.max(1,fw-1)),
      math.floor(y*255/math.max(1,fh-1)),
      ((math.floor(x/12)+math.floor(y/12))%2)*255)
  end end
  local frame=table.concat(bytes)
  local okFrame,frameErr=pcall(function()
    mon.framebufferCreate(fw,fh)
    mon.framebufferSubmit(frame)
  end)
  if not okFrame then return result("video","FAIL","RGB frame submit: "..tostring(frameErr)) end
  return result("video","PASS",("%s RGB888 %dx%d frame submitted (%d bytes)"):format(name,fw,fh,#frame),
    {monitor=name,width=fw,height=fh,bytes=#frame,format=info.format})
end

function M.run(ctx,opts)
  opts=opts or {}
  local machine=config.machine()
  local started=now()
  local checks={}
  checks[#checks+1]=video_test(machine)
  checks[#checks+1]=audio_test(ctx,machine)

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
