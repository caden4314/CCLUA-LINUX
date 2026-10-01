local M={}

local function copyList(value)
  local out={}
  if type(value)=="table" then for _,v in ipairs(value) do out[#out+1]=tostring(v) end end
  return out
end

function M.new(ctx)
  local self={ctx=ctx,services={},order={},errors={},restartTimers={}}

  local function recordError(svc,err)
    svc.lastError=tostring(err)
    self.errors[#self.errors+1]={service=svc.name,error=svc.lastError,time=os.clock()}
  end

  local function restartAllowed(svc,failed)
    if svc.restartPolicy=="always" then return true end
    if svc.restartPolicy=="on-failure" and failed then return true end
    return false
  end

  local function scheduleRestart(svc)
    if svc.pendingRestart then return true end
    if not restartAllowed(svc,true) then return false end
    if svc.restarts>=svc.maxRestarts then
      svc.state="failed"
      return false
    end
    local delay=svc.restartDelay*(2^math.min(svc.restarts,4))
    local timer=os.startTimer(delay)
    svc.pendingRestart=timer
    svc.nextRestartIn=delay
    self.restartTimers[timer]=svc.name
    return true
  end

  function self:register(name,factory,opts)
    if self.services[name] then return nil,"service exists" end
    opts=opts or {}
    local protected=opts.protected==true
    local svc={
      name=name,factory=factory,protected=protected,critical=opts.critical==true,
      state="registered",instance=nil,restarts=0,lastError=nil,startedAt=nil,
      depends=copyList(opts.depends),restartPolicy=opts.restartPolicy or (protected and "on-failure" or "never"),
      restartDelay=tonumber(opts.restartDelay) or 1,maxRestarts=tonumber(opts.maxRestarts) or (protected and 5 or 0),
      pendingRestart=nil,nextRestartIn=nil,
    }
    self.services[name]=svc
    self.order[#self.order+1]=name
    return svc
  end

  function self:start(name,stack)
    local svc=self.services[name]
    if not svc then return nil,"service not found" end
    if svc.state=="running" then return true end
    stack=stack or {}
    if stack[name] then return nil,"dependency cycle at "..name end
    stack[name]=true
    for _,depName in ipairs(svc.depends) do
      local dep=self.services[depName]
      if not dep then stack[name]=nil;return nil,"missing dependency: "..depName end
      local ok,err=self:start(depName,stack)
      if not ok then
        svc.state="blocked";recordError(svc,"dependency "..depName..": "..tostring(err))
        stack[name]=nil
        return nil,svc.lastError
      end
    end
    stack[name]=nil

    local ok,instance=pcall(svc.factory,self.ctx)
    if not ok then
      svc.state="failed";recordError(svc,instance);scheduleRestart(svc)
      return nil,svc.lastError
    end
    svc.instance=instance or {}
    if svc.instance.start then
      local sok,serr=pcall(svc.instance.start)
      if not sok then
        svc.instance=nil;svc.state="failed";recordError(svc,serr);scheduleRestart(svc)
        return nil,svc.lastError
      end
    end
    svc.state="running";svc.startedAt=os.clock();svc.lastError=nil
    svc.pendingRestart=nil;svc.nextRestartIn=nil
    return true
  end

  function self:startAll()
    local allOk=true
    for _,name in ipairs(self.order) do
      local ok,err=self:start(name)
      if not ok then
        allOk=false
        if self.services[name].critical then return nil,name..": "..tostring(err) end
      end
    end
    return allOk
  end

  function self:stop(name,internal)
    local svc=self.services[name]
    if not svc then return nil,"service not found" end
    if svc.protected and not internal then return nil,"protected service" end
    if svc.pendingRestart then
      pcall(os.cancelTimer,svc.pendingRestart)
      self.restartTimers[svc.pendingRestart]=nil
      svc.pendingRestart=nil;svc.nextRestartIn=nil
    end
    if svc.instance and svc.instance.stop then pcall(svc.instance.stop) end
    svc.state="stopped";svc.instance=nil
    return true
  end

  function self:restart(name,internal)
    local svc=self.services[name]
    if not svc then return nil,"service not found" end
    if svc.protected and not internal then return nil,"protected service" end
    if svc.instance and svc.instance.stop then pcall(svc.instance.stop) end
    svc.instance=nil;svc.state="registered";svc.restarts=svc.restarts+1
    return self:start(name)
  end

  local function failService(svc,err)
    recordError(svc,err)
    if svc.instance and svc.instance.stop then pcall(svc.instance.stop) end
    svc.instance=nil;svc.state="failed"
    scheduleRestart(svc)
  end

  function self:event(event,...)
    if event=="timer" then
      local timer=(...)
      local name=self.restartTimers[timer]
      if name then
        self.restartTimers[timer]=nil
        local svc=self.services[name]
        if svc then
          svc.pendingRestart=nil;svc.nextRestartIn=nil
          svc.restarts=svc.restarts+1
          svc.state="registered"
          local ok,err=self:start(name)
          if not ok and svc.critical and not svc.pendingRestart then
            os.queueEvent("cclua_service_critical",name,tostring(err))
          end
        end
      end
    end

    for _,name in ipairs(self.order) do
      local svc=self.services[name]
      if svc.state=="running" and svc.instance and svc.instance.event then
        local ok,err=pcall(svc.instance.event,event,...)
        if not ok then failService(svc,err) end
      end
    end
  end

  function self:snapshot()
    local out={}
    for _,name in ipairs(self.order) do
      local svc=self.services[name]
      out[name]={
        state=svc.state,protected=svc.protected,critical=svc.critical,
        restarts=svc.restarts,lastError=svc.lastError,
        uptime=svc.startedAt and svc.state=="running" and (os.clock()-svc.startedAt) or 0,
        depends=copyList(svc.depends),restartPolicy=svc.restartPolicy,
        maxRestarts=svc.maxRestarts,pendingRestart=svc.pendingRestart~=nil,
        nextRestartIn=svc.nextRestartIn,
      }
      if svc.instance and svc.instance.status then
        local ok,status=pcall(svc.instance.status)
        if ok then out[name].detail=status end
      end
    end
    return out
  end

  function self:get(name)
    local svc=self.services[name]
    return svc and svc.instance or nil
  end

  return self
end

return M
