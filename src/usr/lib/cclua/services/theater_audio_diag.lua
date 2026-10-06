-- Remote theater speaker diagnostics for Audio Engine v2.
local M={}
local RATE,BLOCK=48000,131072

local function tone_block(freq,level,startSample,count,total)
  local out={}
  for j=1,count do
    local i=startSample+j
    local edge=math.min(1,i/160,(total+1-i)/160)
    out[j]=math.floor(math.sin((i-1)*2*math.pi*freq/RATE)*level*edge)
  end
  return out
end

function M.snapshot(speakers)
  local out={}
  for i,sp in ipairs(speakers or {}) do out[i]={index=i,name=sp.name,type=peripheral.getType(sp.name)} end
  return out
end

function M.start(ctx,owner,speakers,opts,onUpdate)
  opts=type(opts)=="table" and opts or {}
  local target=tonumber(opts.index)
  local freq=tonumber(opts.frequency) or 880
  local seconds=math.max(0.05,math.min(10,tonumber(opts.seconds) or 1))
  local level=math.max(1,math.min(127,tonumber(opts.level) or 28))
  local volume=math.max(0.1,math.min(3,tonumber(opts.volume) or 1))
  local selected={}
  for i,sp in ipairs(speakers or {}) do if not target or target==i then selected[#selected+1]=sp end end
  if #selected==0 then return nil,"speaker index not found" end

  local proc,err=ctx.kernel.process.create{ppid=ctx.process.pid,name="cclua-theater-audio-diag",
    uid=ctx.process.uid,gid=ctx.process.gid,groups=ctx.process.groups,cwd=ctx.process.cwd,
    capabilities=ctx.process.capabilities,argv={"theater-audio-diag"}}
  if not proc then return nil,err end
  local total=math.floor(RATE*seconds)
  local result={running=true,started=os.epoch("utc"),target=target or "all",selected=#selected,
    accepted=0,accepted_blocks=0,retries=0,errors={},frequency=freq,seconds=seconds,
    block_samples=BLOCK,total_samples=total,speakers=M.snapshot(speakers)}
  owner.audio_diag=result;if onUpdate then onUpdate(result) end

  ctx.kernel.scheduler:add(proc,function()
    for _,sp in ipairs(selected) do pcall(sp.obj.stop) end
    local pos=0
    while pos<total do
      local count=math.min(BLOCK,total-pos)
      local pcm=tone_block(freq,level,pos,count,total)
      local pending={};for _,sp in ipairs(selected) do pending[sp.name]=sp end
      while next(pending) do
        for name,sp in pairs(pending) do
          local ok,accepted=pcall(sp.obj.playAudio,pcm,volume)
          if not ok then result.errors[name]=tostring(accepted);pending[name]=nil
          elseif accepted then result.accepted=result.accepted+1;result.accepted_blocks=result.accepted_blocks+1;pending[name]=nil
          else result.retries=result.retries+1 end
        end
        if next(pending) then
          if onUpdate then onUpdate(result) end
          local ev=coroutine.yield("wait_event",{"speaker_audio_empty","terminate"})
          if ev=="terminate" then result.errors.terminate="terminated";break end
        end
      end
      if next(result.errors) then break end
      pos=pos+count;result.samples_submitted=pos
      if onUpdate then onUpdate(result) end
    end
    result.running=false;result.finished=os.epoch("utc")
    result.ok=(result.samples_submitted==total and next(result.errors)==nil)
    if onUpdate then onUpdate(result) end
    return result.ok and 0 or 1
  end)
  return result
end
return M
