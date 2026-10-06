from pathlib import Path
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
audio_path = (ROOT / "src/usr/lib/cclua/services/theater_audio.lua").as_posix()
lua = LuaRuntime(unpack_returned_tuples=True)

lua.execute(f'''
os.epoch=function(_) return 1000 end
audio=dofile("{audio_path}")
child=nil
process={{}}
function process.create(spec)
  child={{pid=42,name=spec.name,state="runnable"}}
  return child
end
function process.exit(pid,code,why)
  if type(pid)=="table" then pid.state="killed" end
end
scheduler={{}}
function scheduler:add(proc,fn)
  proc.co=coroutine.create(fn)
end
ctx={{
  process={{pid=1,uid=0,gid=0,groups={{}},cwd="/",capabilities={{}}}},
  kernel={{process=process,scheduler=scheduler}},
}}
calls={{}}
stopped=0
blocked_once=true
function speaker(name,block)
  return {{name=name,obj={{
    stop=function() stopped=stopped+1 end,
    playAudio=function(samples,volume)
      calls[#calls+1]={{name=name,first=samples[1],volume=volume}}
      if block and blocked_once then blocked_once=false;return false end
      return true
    end,
  }}}}
end
''')

lua.execute(r'''
local owner={active=true}
local speakers={speaker("left",false),speaker("right",true)}
local engine,err=audio.start(ctx,owner,speakers,3.0)
assert(engine,err)
assert(stopped==2,"engine must flush each speaker at start")
assert(audio.enqueue(engine,{32,16,-8},3)==1)

local ok,kind,filter=coroutine.resume(child.co)
assert(ok,tostring(kind))
assert(kind=="wait_event","backpressure must wait for speaker_audio_empty")
assert(#calls==2,"first epoch must attempt every speaker")
local status=audio.status(engine)
assert(status.head_pending==1,"only rejected speaker should remain pending")
assert(status.committed_epoch==0,"epoch committed before all speakers accepted")

ok,kind,filter=coroutine.resume(child.co,"speaker_audio_empty","right")
assert(ok,tostring(kind))
status=audio.status(engine)
assert(status.committed_epoch==1,"epoch did not commit after retry")
assert(status.head_pending==0,"pending speakers remained after commit")
assert(#calls==3,"accepted speaker was incorrectly replayed during retry")
assert(calls[1].volume==3.0 and calls[2].volume==3.0,"volume changed")
assert(calls[1].first==32 and calls[2].first==32,"PCM changed")

audio.stop(ctx,engine)
assert(engine.active==false,"engine stop failed")
assert(stopped>=4,"engine stop did not flush speakers")
''')
print("THEATER_AUDIO_V2_OK")
