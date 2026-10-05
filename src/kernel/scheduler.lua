local M={}
local INPUT_EVENTS={
  key=true,key_up=true,char=true,paste=true,
  mouse_click=true,mouse_drag=true,mouse_up=true,mouse_scroll=true,
  term_resize=true,terminate=true,
}

local function matches_filter(filter,name)
  if filter==nil then return true end
  if type(filter)=="string" then return filter==name end
  if type(filter)=="table" then
    if filter[name]==true then return true end
    for _,v in ipairs(filter) do if v==name then return true end end
  end
  return false
end

function M.new(kernel)
  local s={kernel=kernel,runnable={},running=false}

  local function queue_pid(pid)
    s.runnable[#s.runnable+1]=pid
  end

  local function pop_pending(p,filter)
    for i,ev in ipairs(p.pending_events or {}) do
      if matches_filter(filter,ev[1]) then
        table.remove(p.pending_events,i)
        return ev
      end
    end
  end

  function s:add(p,fn)
    p.coroutine=coroutine.create(fn)
    p.state="runnable"
    queue_pid(p.pid)
    return p
  end

  function s:wake(pid,ev)
    local p=kernel.process.get(pid)
    if not p or kernel.process.is_terminal(p) then return false end
    if p.state=="stopped" then return false end
    p.state="runnable"
    p.event_filter=nil
    p.wake_at=nil
    p.resume_event=ev
    queue_pid(pid)
    return true
  end

  function s:send_event(pid,ev)
    local p=kernel.process.get(pid)
    if not p or kernel.process.is_terminal(p) then return nil,"ESRCH" end
    ev=ev or {}
    if p.state=="waiting" and matches_filter(p.event_filter,ev[1]) then
      return self:wake(pid,ev)
    end
    p.pending_events=p.pending_events or {}
    p.pending_events[#p.pending_events+1]=ev
    return true
  end

  function s:send_group(pgid,ev)
    local sent=0
    for _,p in ipairs(kernel.process.group(pgid)) do
      if self:send_event(p.pid,ev) then sent=sent+1 end
    end
    return sent
  end

  function s:resume(p,...)
    if not p or kernel.process.is_terminal(p) then return false end
    if coroutine.status(p.coroutine)=="dead" then return false end
    p.state="running"
    p.started_at=p.started_at or (os.epoch and os.epoch("utc") or 0)
    p.cpu_resumes=p.cpu_resumes+1

    local oldTerm
    if p.terminal and term and term.current and term.redirect then
      oldTerm=term.current()
      term.redirect(p.terminal)
    end
    local ok,req,arg=coroutine.resume(p.coroutine,...)
    if oldTerm then term.redirect(oldTerm) end

    if not ok then
      p.error=tostring(req)
      p.exit_code=1
      p.state="crashed"
      local trace=p.error
      if debug and debug.traceback then
        local traceOk,traceValue=pcall(debug.traceback,p.coroutine,p.error)
        if traceOk and traceValue then trace=tostring(traceValue) end
      end
      if #trace>6000 then trace=trace:sub(1,6000).."\n<truncated>" end
      p.traceback=trace
      p.ended_at=(os.epoch and os.epoch("utc") or 0)
      kernel.log.write("error","scheduler","process crashed: "..p.name,{
        error=p.error,traceback=p.traceback,state=p.state,cpu_resumes=p.cpu_resumes
      },p.pid)
      if os.queueEvent then os.queueEvent("cclua_process_exit",p.pid,p.exit_code,"crashed") end
      return false
    end

    if coroutine.status(p.coroutine)=="dead" then
      local changed=kernel.process.exit(p,tonumber(req) or 0)
      if changed and os.queueEvent then
        os.queueEvent("cclua_process_exit",p.pid,p.exit_code,p.state)
      end
      return false
    end

    if req=="wait_event" then
      local pending=pop_pending(p,arg)
      if pending then
        p.state="runnable"
        p.resume_event=pending
        queue_pid(p.pid)
      else
        p.state="waiting"
        p.event_filter=arg
      end
    elseif req=="sleep" then
      p.state="sleeping"
      p.wake_at=arg
    elseif req=="stop" then
      p.state="stopped"
      p.stopped_filter=p.event_filter
    elseif type(req)=="string" or req==nil then
      local pending=pop_pending(p,req)
      if pending then
        p.state="runnable"
        p.resume_event=pending
        queue_pid(p.pid)
      else
        p.state="waiting"
        p.event_filter=req
      end
    else
      p.state="runnable"
      queue_pid(p.pid)
    end
    return true
  end

  function s:dispatch(ev)
    ev=ev or {}
    local name=ev[1]
    local now=(os.epoch and os.epoch("utc")) or 0

    for _,p in ipairs(kernel.process.all()) do
      if p.state=="sleeping" and p.wake_at and now>=p.wake_at then
        self:wake(p.pid,{"cclua_sleep"})
      elseif p.state=="waiting" and (not p.pty or not INPUT_EVENTS[name])
        and matches_filter(p.event_filter,name) then
        self:wake(p.pid,ev)
      end
    end

    local q=self.runnable
    self.runnable={}
    local seen={}
    for _,pid in ipairs(q) do
      if not seen[pid] then
        seen[pid]=true
        local p=kernel.process.get(pid)
        if p and p.state=="runnable" then
          local rev=p.resume_event
          p.resume_event=nil
          if rev then self:resume(p,table.unpack(rev))
          else self:resume(p) end
        end
      end
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
  function s:stop()
    self.running=false
  end

  function s.sleep(sec)
    local now=(os.epoch and os.epoch("utc")) or 0
    return coroutine.yield("sleep",now+math.floor((tonumber(sec) or 0)*1000))
  end

  function s.wait_event(filter)
    return coroutine.yield("wait_event",filter)
  end

  return s
end

function M.wait_event(filter)
  return coroutine.yield("wait_event",filter)
end

function M.sleep(sec)
  local now=(os.epoch and os.epoch("utc")) or 0
  return coroutine.yield("sleep",now+math.floor((tonumber(sec) or 0)*1000))
end

return M
