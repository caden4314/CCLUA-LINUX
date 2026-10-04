return function(ctx)
  local net=dofile("/usr/lib/cclua/net.lua")
  local machine=dofile("/usr/lib/cclua/config.lua").machine()

  local heartbeatSeconds=tonumber(machine.mesh_heartbeat_seconds) or 8
  local snapshotSeconds=tonumber(machine.network_snapshot_seconds) or 5

  local opened=net.open_all_modems()
  ctx.unit.details={
    modems=opened,
    heartbeat_seconds=heartbeatSeconds,
    snapshot_seconds=snapshotSeconds
  }
  ctx.kernel.log.write("info","netd","network service online",ctx.unit.details,ctx.process.pid)

  local heartbeat=os.startTimer(1)
  local snapshot=os.startTimer(snapshotSeconds)
  local modemRefreshTimer=nil

  local function status()
    return {
      uptime=os.clock and os.clock() or 0,
      processes=#ctx.kernel.process.all(),
      services=(function()
        local n=0
        for _,u in ipairs(ctx.kernel.services:list()) do
          if u.state=="active" then n=n+1 end
        end
        return n
      end)(),
      peripherals=(function()
        local n=0
        for _ in pairs(ctx.kernel.device.devices) do n=n+1 end
        return n
      end)()
    }
  end

  while true do
    local ev,a,b,c=coroutine.yield("wait_event")

    if ev=="timer" and a==heartbeat then
      net.broadcast("heartbeat",{status=status()})
      heartbeat=os.startTimer(heartbeatSeconds)

    elseif ev=="timer" and a==snapshot then
      -- Persist peer state in batches instead of once for every incoming
      -- heartbeat. With a large fleet this avoids an O(N^2) burst of disk
      -- writes while preserving a fresh network inventory.
      net.snapshot()
      snapshot=os.startTimer(snapshotSeconds)

    elseif ev=="rednet_message" then
      local sender,msg,protocol=a,b,c
      if protocol==net.protocol then
        local accepted=net.accept(sender,msg)
        if accepted and accepted.kind=="ping" then
          net.send(sender,"pong",{nonce=accepted.payload and accepted.payload.nonce})
        end
      end

    elseif ev=="peripheral" or ev=="peripheral_detach" then
      if modemRefreshTimer and os.cancelTimer then pcall(os.cancelTimer,modemRefreshTimer) end
      modemRefreshTimer=os.startTimer(0.40)

    elseif ev=="timer" and modemRefreshTimer and a==modemRefreshTimer then
      modemRefreshTimer=nil
      opened=net.open_all_modems()
      ctx.unit.details.modems=opened
    end
  end
end
