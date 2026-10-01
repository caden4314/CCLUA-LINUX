local M={}

function M.new(ctx)
  local self={
    ctx=ctx,
    running=true,
    eventCount=0,
    started=os.clock(),
    panic=nil,
  }

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
    }
  end

  return self
end

return M
