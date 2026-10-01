local M={}
local Scheduler=ISO.require("system/kernel/scheduler.lua")

function M.new(ctx)
  local self={
    ctx=ctx,
    running=true,
    eventCount=0,
    started=os.clock(),
    panic=nil,
    scheduler=Scheduler.new(ctx),
  }
  ctx.scheduler=self.scheduler

  function self:spawn(name,fn,opts)
    return self.scheduler:spawn(name,fn,opts)
  end

  function self:tasks(includeFinished)
    return self.scheduler:list(includeFinished)
  end

  function self:kill(pid,reason)
    return self.scheduler:kill(pid,reason,false)
  end

  function self:dispatch(event,...)
    self.eventCount=self.eventCount+1

    -- Kernel services see hardware/network/timer events before userspace.
    if ctx.services then
      local ok,err=pcall(ctx.services.event,ctx.services,event,...)
      if not ok then
        self.panic="service dispatcher: "..tostring(err)
        return nil,self.panic
      end
    end

    -- Cooperative kernel/userspace tasks receive the same event stream next.
    local tok,terr=pcall(self.scheduler.dispatch,self.scheduler,event,...)
    if not tok then
      self.panic="scheduler dispatcher: "..tostring(terr)
      return nil,self.panic
    end

    -- Then the desktop/session receives the event.
    if ctx.wm then
      local ok,err=pcall(ctx.wm.handle,ctx.wm,event,...)
      if not ok then
        self.panic="desktop dispatcher: "..tostring(err)
        return nil,self.panic
      end
    end
    return true
  end

  function self:run()
    while self.running do
      local ev={os.pullEventRaw()}
      if ev[1]=="terminate" then
        -- Ctrl+T is a userspace request. The kernel remains in control.
        os.queueEvent("cclua_interrupt")
      else
        local ok,err=self:dispatch(table.unpack(ev))
        if not ok then return nil,err end
      end
    end
    return true
  end

  function self:stop()
    self.running=false
  end

  function self:status()
    return {
      uptime=os.clock()-self.started,
      events=self.eventCount,
      panic=self.panic,
      scheduler=self.scheduler:status(),
    }
  end

  return self
end

return M
