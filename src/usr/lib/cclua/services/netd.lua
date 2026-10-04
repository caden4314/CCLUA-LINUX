return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local net=dofile("/usr/lib/cclua/net.lua")
  local machine=config.machine()

  local heartbeatSeconds=tonumber(machine.mesh_heartbeat_seconds) or 8
  local snapshotSeconds=tonumber(machine.network_snapshot_seconds) or 5
  local probeSeconds=tonumber(machine.manager_probe_seconds) or 3
  local managerId=tonumber(machine.manager_computer_id) or 0
  local isManager=machine.role=="manager" or machine.role=="network-manager"

  local opened=net.open_all_modems()
  local pendingNonce=nil
  local pendingSentAt=nil
  local lastPong=nil
  local lastManagerMessage=nil
  local rttMs=nil
  local missed=0
  local reopenCount=0
  local linkState=#opened>0 and (isManager and "ONLINE" or "CHECKING") or "NO_MODEM"

  ctx.unit.details={
    modems=opened,
    heartbeat_seconds=heartbeatSeconds,
    snapshot_seconds=snapshotSeconds,
    probe_seconds=probeSeconds,
    manager_id=managerId,
  }
  ctx.kernel.log.write("info","netd","network service online",ctx.unit.details,ctx.process.pid)

  local heartbeat=os.startTimer(1)
  local snapshot=os.startTimer(snapshotSeconds)
  local probe=os.startTimer(1.5)
  local modemRefreshTimer=nil

  local function now()
    return os.epoch and os.epoch("utc") or 0
  end

  local function active_services()
    local n=0
    for _,u in ipairs(ctx.kernel.services:list()) do
      if u.state=="active" then n=n+1 end
    end
    return n
  end

  local function peripheral_count()
    local n=0
    for _ in pairs(ctx.kernel.device.devices or {}) do n=n+1 end
    return n
  end

  local function status()
    return {
      uptime=os.clock and os.clock() or 0,
      processes=#ctx.kernel.process.all(),
      services=active_services(),
      peripherals=peripheral_count(),
      link_state=linkState,
      manager_rtt_ms=rttMs,
      missed_probes=missed,
    }
  end

  local function health_payload()
    local age=nil
    if lastManagerMessage then age=math.max(0,(now()-lastManagerMessage)/1000) end
    return {
      schema=2,
      state=linkState,
      online=linkState=="ONLINE",
      manager_id=managerId,
      manager_rtt_ms=rttMs,
      missed_probes=missed,
      last_pong=lastPong,
      last_manager_message=lastManagerMessage,
      manager_age_seconds=age,
      pending_nonce=pendingNonce,
      modems=opened,
      modem_count=#opened,
      reopen_count=reopenCount,
      stats=net.stats,
      peer_count=(function() local n=0 for _ in pairs(net.peers or {}) do n=n+1 end return n end)(),
      timestamp=now(),
    }
  end

  local function persist_health()
    config.write_json("/var/lib/cclua/network-health.json",health_payload())
  end

  local function reopen_modems(reason)
    opened=net.open_all_modems()
    reopenCount=reopenCount+1
    ctx.unit.details.modems=opened
    if #opened==0 then
      linkState="NO_MODEM"
    elseif isManager then
      linkState="ONLINE"
    elseif linkState=="NO_MODEM" then
      linkState="CHECKING"
    end
    ctx.kernel.log.write(#opened>0 and "info" or "warning","netd","management modem refresh",{
      reason=reason,modems=opened,reopen_count=reopenCount
    },ctx.process.pid)
    persist_health()
  end

  local function send_probe()
    if isManager then
      linkState=#opened>0 and "ONLINE" or "NO_MODEM"
      return
    end
    if #opened==0 then
      linkState="NO_MODEM"
      reopen_modems("probe-no-modem")
      return
    end

    local stamp=now()
    if pendingNonce and pendingSentAt and stamp-pendingSentAt>=probeSeconds*1000 then
      local managerRecentlySeen=lastManagerMessage
        and (stamp-lastManagerMessage)<(probeSeconds*2000)
      if managerRecentlySeen then
        -- A heartbeat/status packet is still proof the link is alive even if
        -- one dedicated RTT probe response was lost.
        missed=0
        linkState="ONLINE"
      else
        missed=missed+1
        if missed>=3 then linkState="DEGRADED" end
        if missed>=5 then reopen_modems("manager-probe-misses") end
      end
    end

    local nonce=("%d-%d"):format(os.getComputerID(),stamp)
    local _,sent=net.send(managerId,"ping",{nonce=nonce,sent_at=stamp})
    if sent then
      pendingNonce=nonce
      pendingSentAt=stamp
      if not lastManagerMessage and missed==0 then linkState="CHECKING" end
    else
      missed=missed+1
      linkState=missed>=3 and "DEGRADED" or "CHECKING"
    end
  end

  persist_health()

  while true do
    local ev,a,b,c=coroutine.yield("wait_event",{
      "timer","rednet_message","peripheral","peripheral_detach","terminate"
    })

    if ev=="timer" and a==heartbeat then
      net.broadcast("heartbeat",{status=status()})
      heartbeat=os.startTimer(heartbeatSeconds)

    elseif ev=="timer" and a==snapshot then
      net.snapshot({health=health_payload()})
      persist_health()
      snapshot=os.startTimer(snapshotSeconds)

    elseif ev=="timer" and a==probe then
      send_probe()
      persist_health()
      probe=os.startTimer(probeSeconds)

    elseif ev=="rednet_message" then
      local sender,msg,protocol=a,b,c
      if protocol==net.protocol then
        local accepted=net.accept(sender,msg)
        if accepted then
          if tonumber(sender)==managerId then
            lastManagerMessage=now()
            if #opened>0 then linkState="ONLINE" end
          end

          if accepted.kind=="ping" then
            net.send(sender,"pong",{
              nonce=accepted.payload and accepted.payload.nonce,
              sent_at=accepted.payload and accepted.payload.sent_at,
              received_at=now(),
            })
          elseif accepted.kind=="pong" and tonumber(sender)==managerId then
            local nonce=accepted.payload and accepted.payload.nonce
            if pendingNonce and nonce==pendingNonce then
              local stamp=now()
              rttMs=math.max(0,stamp-(pendingSentAt or stamp))
              lastPong=stamp
              lastManagerMessage=stamp
              pendingNonce=nil
              pendingSentAt=nil
              missed=0
              linkState=#opened>0 and "ONLINE" or "NO_MODEM"
            end
          end
        end
      end

    elseif ev=="peripheral" or ev=="peripheral_detach" then
      if modemRefreshTimer and os.cancelTimer then pcall(os.cancelTimer,modemRefreshTimer) end
      modemRefreshTimer=os.startTimer(0.40)

    elseif ev=="timer" and modemRefreshTimer and a==modemRefreshTimer then
      modemRefreshTimer=nil
      reopen_modems("debounced-peripheral-events")

    elseif ev=="terminate" then
      persist_health()
      return 0
    end
  end
end
