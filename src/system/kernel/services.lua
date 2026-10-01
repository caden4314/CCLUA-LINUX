local M={}

function M.new(ctx)
  local self={ctx=ctx,services={},order={},errors={}}

  function self:register(name,factory,opts)
    if self.services[name] then return nil,"service exists" end
    opts=opts or {}
    local svc={
      name=name,factory=factory,protected=opts.protected==true,
      critical=opts.critical==true,state="registered",instance=nil,
      restarts=0,lastError=nil,startedAt=nil,
    }
    self.services[name]=svc
    self.order[#self.order+1]=name
    return svc
  end

  function self:start(name)
    local svc=self.services[name]
    if not svc then return nil,"service not found" end
    if svc.state=="running" then return true end
    local ok,instance=pcall(svc.factory,self.ctx)
    if not ok then
      svc.state="failed";svc.lastError=tostring(instance)
      self.errors[#self.errors+1]={service=name,error=svc.lastError,time=os.clock()}
      return nil,svc.lastError
    end
    svc.instance=instance or {}
    if svc.instance.start then
      local sok,serr=pcall(svc.instance.start)
      if not sok then
        svc.state="failed";svc.lastError=tostring(serr)
        return nil,svc.lastError
      end
    end
    svc.state="running";svc.startedAt=os.clock()
    return true
  end
  function self:startAll()
    local ok=true
    for _,name in ipairs(self.order) do
      local started,err=self:start(name)
      if not started then
        ok=false
        local svc=self.services[name]
        if svc.critical then return nil,name..": "..tostring(err) end
      end
    end
    return ok
  end

  function self:restart(name,internal)
    local svc=self.services[name]
    if not svc then return nil,"service not found" end
    if svc.protected and not internal then return nil,"protected service" end
    if svc.instance and svc.instance.stop then pcall(svc.instance.stop) end
    svc.instance=nil;svc.state="registered";svc.restarts=svc.restarts+1
    return self:start(name)
  end

  function self:stop(name,internal)
    local svc=self.services[name]
    if not svc then return nil,"service not found" end
    if svc.protected and not internal then return nil,"protected service" end
    if svc.instance and svc.instance.stop then pcall(svc.instance.stop) end
    svc.state="stopped";svc.instance=nil
    return true
  end

  function self:event(event,...)
    for _,name in ipairs(self.order) do
      local svc=self.services[name]
      if svc.state=="running" and svc.instance and svc.instance.event then
        local ok,err=pcall(svc.instance.event,event,...)
        if not ok then
          svc.lastError=tostring(err);svc.state="failed"
          self.errors[#self.errors+1]={service=name,error=svc.lastError,time=os.clock()}
          if svc.protected then self:restart(name,true) end
        end
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
        uptime=svc.startedAt and (os.clock()-svc.startedAt) or 0,
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
