-- Theater Audio Engine v2.
-- Deliberately follows the proven CCLUA Music speaker contract:
-- playAudio -> wait for speaker_audio_empty on backpressure -> retry unchanged PCM.
local M={}

local function copy_speakers(speakers)
  local out={}
  for i,sp in ipairs(speakers or {}) do out[i]=sp end
  return out
end

function M.start(ctx,owner,speakers,volume)
  assert(type(ctx)=="table","audio engine requires service context")
  assert(type(owner)=="table","audio engine requires session")
  speakers=copy_speakers(speakers)
  assert(#speakers>0,"audio engine requires speakers")

  local engine={
    generation=(owner.audio_generation or 0)+1,
    speakers=speakers,
    volume=volume or 1,
    queue={},
    next_epoch=1,
    committed_epoch=0,
    active=true,
  }
  owner.audio_generation=engine.generation

  -- Start from an empty CC:Tweaked speaker queue, exactly as a fresh Music
  -- playback session does.
  for _,sp in ipairs(speakers) do pcall(sp.obj.stop) end

  local parent=ctx.process
  local proc,err=ctx.kernel.process.create{
    ppid=parent.pid,name="cclua-theater-audio-v2",
    uid=parent.uid,gid=parent.gid,groups=parent.groups,
    cwd=parent.cwd,capabilities=parent.capabilities,
    argv={"theater-audio-v2"},
  }
  if not proc then return nil,err end
  engine.pid=proc.pid

  ctx.kernel.scheduler:add(proc,function()
    while engine.active and owner.active do
      local epoch=engine.queue[1]
      if not epoch then
        coroutine.yield("sleep",(os.epoch and os.epoch("utc") or 0)+5)
      else
        while engine.active and owner.active and next(epoch.pending) do
          for name,sp in pairs(epoch.pending) do
            local ok,accepted=pcall(sp.obj.playAudio,epoch.audio,engine.volume)
            if not ok then
              engine.last_error=tostring(accepted)
              engine.active=false
              break
            elseif accepted then
              epoch.pending[name]=nil
            end
          end
          if next(epoch.pending) and engine.active then
            coroutine.yield("wait_event",{"speaker_audio_empty","terminate"})
          end
        end

        if engine.active and not next(epoch.pending) then
          table.remove(engine.queue,1)
          engine.committed_epoch=epoch.id
          engine.committed_samples=epoch.samples
          if os.queueEvent then
            os.queueEvent("cclua_theater_audio_committed",
              engine.generation,epoch.id,epoch.samples)
          end
        end
      end
    end
    for _,sp in ipairs(engine.speakers) do pcall(sp.obj.stop) end
    return engine.last_error and 1 or 0
  end)
  return engine
end

function M.enqueue(engine,audio,samples)
  if not engine or not engine.active then return nil,"audio engine stopped" end
  local pending={}
  for _,sp in ipairs(engine.speakers) do pending[sp.name]=sp end
  local id=engine.next_epoch
  engine.next_epoch=id+1
  engine.queue[#engine.queue+1]={
    id=id,audio=audio,samples=samples or 0,pending=pending,
  }
  return id
end

function M.stop(ctx,engine)
  if not engine then return end
  engine.active=false
  for _,sp in ipairs(engine.speakers or {}) do pcall(sp.obj.stop) end
  if engine.pid and ctx.kernel.process and ctx.kernel.process.exit then
    pcall(ctx.kernel.process.exit,engine.pid,143,"killed")
  end
end

function M.status(engine)
  if not engine then return {active=false} end
  local pending=0
  local head=engine.queue[1]
  if head then for _ in pairs(head.pending) do pending=pending+1 end end
  return {
    active=engine.active,
    generation=engine.generation,
    speakers=#engine.speakers,
    queue_depth=#engine.queue,
    head_pending=pending,
    committed_epoch=engine.committed_epoch,
    committed_samples=engine.committed_samples or 0,
    error=engine.last_error,
  }
end

return M
