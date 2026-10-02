return function(ctx)
  local net=dofile("/usr/lib/cclua/net.lua")
  local opened=net.open_all_modems()
  ctx.unit.details={modems=opened}
  ctx.kernel.log.write("info","netd","network service online",{modems=opened},ctx.process.pid)

  local heartbeat=os.startTimer(1)
  while true do
    local ev,a,b,c=coroutine.yield("wait_event")
    if ev=="timer" and a==heartbeat then
      local status={
        uptime=os.clock and os.clock() or 0,
        processes=#ctx.kernel.process.all(),
        services=(function() local n=0 for _,u in ipairs(ctx.kernel.services:list()) do if u.state=="active" then n=n+1 end end return n end)(),
        peripherals=(function() local n=0 for _ in pairs(ctx.kernel.device.devices) do n=n+1 end return n end)()
      }
      net.broadcast("heartbeat",{status=status})
      net.snapshot()
      heartbeat=os.startTimer(2)
    elseif ev=="rednet_message" then
      local sender,msg,protocol=a,b,c
      if protocol==net.protocol then
        local accepted=net.accept(sender,msg)
        if accepted then
          if accepted.kind=="ping" then
            net.send(sender,"pong",{nonce=accepted.payload and accepted.payload.nonce})
          elseif accepted.kind=="heartbeat" then
            net.snapshot()
          end
        end
      end
    end
  end
end
