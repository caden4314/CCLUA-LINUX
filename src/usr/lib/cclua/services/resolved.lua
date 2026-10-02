return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local m=config.machine()
  ctx.unit.details={
    dns_server=m.manager or "10.27.0.1",
    search_domain="cclua"
  }
  ctx.kernel.log.write("info","resolved","resolver online",ctx.unit.details,ctx.process.pid)
  while true do coroutine.yield("wait_event") end
end
