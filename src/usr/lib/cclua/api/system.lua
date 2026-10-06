local M={}
local config=dofile("/usr/lib/cclua/config.lua")
local native=dofile("/usr/lib/cclua/native.lua")

local function count_map(value)
  local n=0
  for _ in pairs(value or {}) do n=n+1 end
  return n
end

local function service_snapshot(ctx)
  local rows={}
  local active,failed,total,restarts=0,0,0,0
  for _,unit in ipairs(ctx.kernel.services:list()) do
    if not unit.reference or unit.exec then
      total=total+1
      if unit.state=="active" then active=active+1 end
      if unit.state=="failed" then failed=failed+1 end
      restarts=restarts+(tonumber(unit.total_restarts) or 0)
      rows[#rows+1]={
        name=unit.name,state=unit.state,description=unit.description,
        enabled=unit.enabled==true,pid=unit.pid,error=unit.error,
        restarts=tonumber(unit.total_restarts) or 0,
      }
    end
  end
  table.sort(rows,function(a,b)return tostring(a.name)<tostring(b.name) end)
  return {total=total,active=active,failed=failed,restarts=restarts,units=rows}
end
function M.snapshot(ctx)
  local machine=config.machine()
  local status=config.read_json("/var/lib/cclua/status.json",{}) or {}
  local post=config.read_json("/var/lib/cclua/post.json",{}) or {}
  local network=config.read_json("/var/lib/cclua/network-health.json",{}) or {}
  local net=config.read_json("/var/lib/cclua/network.json",{}) or {}
  local update=config.read_json("/var/lib/cclua/update-state.json",{}) or {}
  local session=config.read_json("/var/lib/cclua/session-health.json",{}) or {}
  local apphost=config.read_json("/var/lib/cclua/apphost.json",{}) or {}
  local services=service_snapshot(ctx)
  local processes=ctx.kernel.process.all()
  local peripherals=count_map(ctx.kernel.device and ctx.kernel.device.devices)

  return {
    schema=1,
    host={
      hostname=machine.hostname or "cclua",
      computer_id=os.getComputerID(),
      role=machine.role or "server",
      user=machine.desktop_user or "caden",
      channel=machine.channel or "development",
    },
    system={
      state=status.state or "BOOTING",
      healthy=(status.state or "") == "HEALTHY",
      error_code=tonumber(status.error_code or 0) or 0,
      error_reason=status.error_reason,
      kernel=ctx.kernel.version.version,
      kernel_abi=ctx.kernel.version.kernel_abi,
      uptime_seconds=math.floor(os.clock()),
      process_count=#processes,
      peripheral_count=peripherals,
      services=services,
    },    post={
      state=post.state or "UNKNOWN",pass=post.pass or 0,warn=post.warn or 0,
      fail=post.fail or 0,fatal=post.fatal==true,
    },
    network={
      state=network.state or "CHECKING",
      address=machine.address,network=machine.network,manager=machine.manager,
      manager_id=machine.manager_computer_id,
      manager_rtt_ms=network.manager_rtt_ms,
      manager_age_seconds=network.manager_age_seconds,
      missed_probes=network.missed_probes or 0,
      modem_count=network.modem_count or 0,
      reopen_count=network.reopen_count or 0,
      peer_count=#(net.peers or {}),
      stats=net.stats or {},
    },
    update={
      state=update.state or update.phase or "IDLE",
      percent=tonumber(update.percent) or ((update.state=="CURRENT") and 100 or 0),
      current_commit=update.current_commit or update.commit or update.build or update.version,
      available_commit=update.target_commit or update.available_commit or update.manager_commit,
      manager_state=update.manager_state,
      auto_apply=update.auto_apply~=false,
      last_result=update.last_result,
      current_action=update.current_action,
      current_file=update.current_file,
    },
    native={
      available=native.available(),
      version=native.version(),
      capabilities=native.capabilities(),
      computer=native.computer(),
    },
    session={mode=session.mode,recovery=session.recovery==true},
    apps={
      hostname=apphost.hostname,computer_id=apphost.computer_id,
      items=apphost.apps or {},deployments=apphost.deployments or {},
    },
    services=services.units,
    processes=processes,
    machine=machine,
  }
end

function M.service(ctx,name)
  if not name then return nil end
  return ctx.kernel.services:get(name)
end

return M
