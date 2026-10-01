local M={}
local PORT=9100

function M.new(ctx)
  local self={ctx=ctx,timer=nil,interval=30,lastSent=0,sent=0,lastError=nil}

  local function serviceSummary()
    local out={}
    if not ctx.services then return out end
    for name,state in pairs(ctx.services:snapshot()) do
      out[name]={
        state=state.state,
        restarts=state.restarts,
        failed=state.lastError~=nil,
      }
    end
    return out
  end

  local function payload()
    local peripheralSummary=ctx.peripherals and ctx.peripherals:summary() or {count=0,types={}}
    local runtime=ctx.runtime and ctx.runtime:status() or {}
    local net=ctx.services and ctx.services:get("netd")
    local netStatus=net and net.status and net.status() or {}
    return {
      schema="cclua.diagnostics.v1",
      os={
        name=ctx.config.name,
        version=ctx.config.version,
        build=ctx.config.build,
        arch=ctx.config.architecture,
        kernel=ctx.config.kernel,
      },
      runtime={
        uptime=runtime.uptime or os.clock(),
        events=runtime.events or 0,
      },
      display={
        backend=ctx.display.kind,
        width=ctx.compositor.width,
        height=ctx.compositor.height,
        color=ctx.display:isColor(),
      },
      peripherals={
        count=peripheralSummary.count,
        types=peripheralSummary.types,
      },
      network={
        state=netStatus.state,
        modem=netStatus.modem and true or false,
      },
      services=serviceSummary(),
      -- Intentionally excludes username, file paths/content, keys, shell history,
      -- GPS/location, chat text, and application documents.
    }
  end

  local function send()
    local net=ctx.services and ctx.services:get("netd")
    if not net or not net.send then self.lastError="netd unavailable";return false end
    local status=net.status and net.status() or {}
    if status.state~="online" then self.lastError="network offline";return false end
    local id,err=net:send("@server",PORT,payload(),49160,false)
    if not id then self.lastError=err;return false end
    self.sent=self.sent+1;self.lastSent=os.clock();self.lastError=nil
    return true
  end

  function self.start()
    self.timer=os.startTimer(2)
  end

  function self.event(event,a)
    if event=="timer" and a==self.timer then
      send()
      self.timer=os.startTimer(self.interval)
    elseif event=="ccluanet_up" then
      send()
    end
  end

  function self.status()
    return {
      sent=self.sent,
      lastSent=self.lastSent,
      lastError=self.lastError,
      interval=self.interval,
      privacy="coarse-anonymous",
    }
  end

  function self.stop()
    if self.timer then pcall(os.cancelTimer,self.timer) end
  end

  return self
end

M.PORT=PORT
return M
