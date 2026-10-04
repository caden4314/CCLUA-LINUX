local M={}
function M.new(kernel)
 local s={kernel=kernel,runnable={},running=false}
 function s:add(p,fn) p.coroutine=coroutine.create(fn); p.state="runnable"; self.runnable[#self.runnable+1]=p.pid; return p end
 function s:wake(pid)
  local p=kernel.process.get(pid)
  if not p or p.state=="exited" or p.state=="killed" or p.state=="crashed" then return false end
  p.state="runnable"; p.event_filter=nil; self.runnable[#self.runnable+1]=pid; return true
 end
 function s:resume(p,...)
  if not p or coroutine.status(p.coroutine)=="dead" then return false end
  p.state="running"; p.started_at=p.started_at or (os.epoch and os.epoch("utc") or 0); p.cpu_resumes=p.cpu_resumes+1
  local ok,req,arg=coroutine.resume(p.coroutine,...)
  if not ok then
   p.state="crashed"; p.error=tostring(req); p.exit_code=1
   kernel.log.write("error","scheduler","process crashed: "..p.name,{error=p.error},p.pid)
   if os.queueEvent then os.queueEvent("cclua_process_exit",p.pid,p.exit_code,"crashed") end
   return false
  end
  if coroutine.status(p.coroutine)=="dead" then
   kernel.process.exit(p,tonumber(req) or 0)
   if os.queueEvent then os.queueEvent("cclua_process_exit",p.pid,p.exit_code,"exited") end
   return false
  end
  if req=="wait_event" then
   p.state="waiting"; p.event_filter=arg
  elseif req=="sleep" then
   p.state="sleeping"; p.wake_at=arg
  elseif req=="stop" then
   p.state="stopped"
  elseif type(req)=="string" or req==nil then
   -- Native CC:Tweaked APIs yield an optional event filter directly.
   p.state="waiting"; p.event_filter=req
  else
   p.state="runnable"; self.runnable[#self.runnable+1]=p.pid
  end
  return true
 end
 local function matches_filter(filter,name)
  if filter==nil then return true end
  if type(filter)=="string" then return filter==name end
  if type(filter)=="table" then
   if filter[name]==true then return true end
   for _,v in ipairs(filter) do if v==name then return true end end
   return false
  end
  return false
 end
 function s:dispatch(ev)
  local name=ev and ev[1]; local now=(os.epoch and os.epoch("utc")) or 0
  for _,p in ipairs(kernel.process.all()) do
   if p.state=="sleeping" and p.wake_at and now>=p.wake_at then self:wake(p.pid) end
   if p.state=="waiting" and matches_filter(p.event_filter,name) then p.state="runnable"; p.event_filter=nil; self.runnable[#self.runnable+1]=p.pid end
  end
  local q=self.runnable; self.runnable={}; local seen={}
  for _,pid in ipairs(q) do
   if not seen[pid] then seen[pid]=true; local p=kernel.process.get(pid); if p and p.state=="runnable" then self:resume(p,table.unpack(ev or {})) end end
  end
 end
 function s:run()
  self.running=true
  local wakeTimer=nil
  local wakeDeadline=nil

  while self.running do
   self:dispatch({})
   while #self.runnable>0 do self:dispatch({}) end

   local soonest=nil
   local now=(os.epoch and os.epoch("utc")) or 0
   for _,p in ipairs(kernel.process.all()) do
    if p.state=="sleeping" and p.wake_at then
     if not soonest or p.wake_at<soonest then soonest=p.wake_at end
    end
   end

   -- Maintain one CC timer for the nearest sleeper. Previously a new timer
   -- was created after every unrelated event, leaking duplicate timers and
   -- causing delayed event storms on busy computers.
   if soonest and os.startTimer then
    if wakeTimer==nil or wakeDeadline~=soonest then
     if wakeTimer and os.cancelTimer then pcall(os.cancelTimer,wakeTimer) end
     local delay=math.max(0.05,(soonest-now)/1000)
     wakeTimer=os.startTimer(delay)
     wakeDeadline=soonest
    end
   elseif wakeTimer then
    if os.cancelTimer then pcall(os.cancelTimer,wakeTimer) end
    wakeTimer=nil
    wakeDeadline=nil
   end

   local ev={os.pullEventRaw()}
   if ev[1]=="timer" and wakeTimer and ev[2]==wakeTimer then
    wakeTimer=nil
    wakeDeadline=nil
   end
   self:dispatch(ev)
  end

  if wakeTimer and os.cancelTimer then pcall(os.cancelTimer,wakeTimer) end
 end
 function s:stop() self.running=false end
 return s
end
function M.wait_event(f) return coroutine.yield("wait_event",f) end
function M.sleep(sec) local now=(os.epoch and os.epoch("utc")) or 0; return coroutine.yield("sleep",now+math.floor((sec or 0)*1000)) end
return M
