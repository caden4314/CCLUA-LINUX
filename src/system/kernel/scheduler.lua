local M={}

local FINAL={exited=true,crashed=true,killed=true}

local function now()
  return os.clock()
end

function M.new(ctx)
  local self={
    ctx=ctx,tasks={},order={},nextPid=100,
    currentPid=nil,totalCreated=0,totalResumes=0,crashes=0,
  }

  local function finish(task,state,result,err)
    task.state=state
    task.result=result
    task.lastError=err and tostring(err) or nil
    task.endedAt=now()
    task.filter=nil
    if state=="crashed" then
      self.crashes=self.crashes+1
      os.queueEvent("cclua_task_crashed",task.pid,task.name,task.lastError)
    end
  end
  local function resumeTask(task,...)
    if not task or FINAL[task.state] then return false end
    task.state="running"
    task.startedAt=task.startedAt or now()
    task.resumes=task.resumes+1
    self.totalResumes=self.totalResumes+1
    self.currentPid=task.pid
    local result={coroutine.resume(task.co,...)}
    self.currentPid=nil
    local ok=table.remove(result,1)
    if not ok then
      local err=result[1]
      if debug and debug.traceback then
        local tok,tb=pcall(debug.traceback,task.co,tostring(err))
        if tok and tb then err=tb end
      end
      finish(task,"crashed",nil,err)
      return nil,task.lastError
    end
    if task.killPending then
      local reason=task.killPending
      task.killPending=nil
      finish(task,"killed",nil,reason)
      return true
    end
    if coroutine.status(task.co)=="dead" then
      finish(task,"exited",result[1],nil)
      return true,result[1]
    end
    task.filter=type(result[1])=="string" and result[1] or nil
    task.state="waiting"
    return true
  end
  function self:spawn(name,fn,opts)
    if type(fn)~="function" then return nil,"task entry must be a function" end
    opts=opts or {}
    local pid=self.nextPid
    self.nextPid=self.nextPid+1
    local task={
      pid=pid,name=tostring(name or ("task-"..pid)),
      state="ready",filter=nil,protected=opts.protected==true,
      parent=opts.parent or self.currentPid,createdAt=now(),
      startedAt=nil,endedAt=nil,resumes=0,events=0,
      lastError=nil,result=nil,
    }
    task.co=coroutine.create(function()
      return fn(ctx,self,table.unpack(opts.args or {}))
    end)
    self.tasks[pid]=task
    self.order[#self.order+1]=pid
    self.totalCreated=self.totalCreated+1
    local ok,err=resumeTask(task)
    if not ok then return nil,err,pid end
    return pid
  end

  function self:dispatch(event,...)
    local ids={}
    for _,pid in ipairs(self.order) do ids[#ids+1]=pid end
    for _,pid in ipairs(ids) do
      local task=self.tasks[pid]
      if task and task.state=="waiting" and
         (task.filter==nil or task.filter==event) then
        task.events=task.events+1
        resumeTask(task,event,...)
      end
    end
    return true
  end

  function self:send(pid,event,...)
    pid=tonumber(pid)
    local task=pid and self.tasks[pid] or nil
    if not task then return nil,"task not found" end
    if FINAL[task.state] then return nil,"task finished" end
    if task.state~="waiting" then return nil,"task not waiting" end
    if task.filter~=nil and task.filter~=event then return nil,"task is waiting for "..tostring(task.filter) end
    task.events=task.events+1
    return resumeTask(task,event,...)
  end

  function self:kill(pid,reason,internal)
    pid=tonumber(pid)
    local task=pid and self.tasks[pid] or nil
    if not task then return nil,"task not found" end
    if FINAL[task.state] then return nil,"task already finished" end
    if task.protected and not internal then return nil,"protected task" end
    if task.state=="running" then
      task.killPending=reason or "terminated"
      return true
    end
    finish(task,"killed",nil,reason or "terminated")
    return true
  end

  function self:get(pid)
    return self.tasks[tonumber(pid)]
  end

  function self:current()
    return self.currentPid and self.tasks[self.currentPid] or nil
  end
  function self:list(includeFinished)
    local out={}
    for _,pid in ipairs(self.order) do
      local t=self.tasks[pid]
      if t and (includeFinished or not FINAL[t.state]) then
        out[#out+1]={
          pid=t.pid,name=t.name,state=t.state,filter=t.filter,
          protected=t.protected,parent=t.parent,resumes=t.resumes,
          events=t.events,uptime=(t.endedAt or now())-(t.startedAt or t.createdAt),
          error=t.lastError,
        }
      end
    end
    return out
  end

  function self:reap()
    local keep={}
    for _,pid in ipairs(self.order) do
      local t=self.tasks[pid]
      if t and FINAL[t.state] and not t.protected then
        self.tasks[pid]=nil
      else
        keep[#keep+1]=pid
      end
    end
    self.order=keep
  end
  function self:status()
    local s={
      active=0,waiting=0,running=0,exited=0,crashed=0,killed=0,
      totalCreated=self.totalCreated,totalResumes=self.totalResumes,
      crashes=self.crashes,currentPid=self.currentPid,
    }
    for _,pid in ipairs(self.order) do
      local t=self.tasks[pid]
      if t then
        s[t.state]=(s[t.state] or 0)+1
        if not FINAL[t.state] then s.active=s.active+1 end
      end
    end
    return s
  end

  return self
end

return M
