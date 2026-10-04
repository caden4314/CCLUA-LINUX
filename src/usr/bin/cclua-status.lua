local config=dofile("/usr/lib/cclua/config.lua")

local function short(v)
  v=tostring(v or "-")
  if #v>12 then return v:sub(1,12) end
  return v
end

return {main=function(ctx,args)
  local machine=config.machine()
  local status=config.read_json("/var/lib/cclua/status.json",{state="UNKNOWN"})
  local update=config.read_json("/var/lib/cclua/update-state.json",{state="IDLE"})
  local net=config.read_json("/var/lib/cclua/network.json",{peers={},stats={}})

  local active,failed,total=0,0,0
  for _,u in ipairs(ctx.kernel.services:list()) do
    if not u.reference or u.exec then
      total=total+1
      if u.state=="active" then active=active+1 end
      if u.state=="failed" then failed=failed+1 end
    end
  end

  print("CCLUA Ubuntu Server Status")
  print("--------------------------")
  print(("Host:        %s (ID %d)"):format(machine.hostname or "cclua-server",os.getComputerID()))
  print(("Role:        %s"):format(machine.role or "server"))
  print(("State:       %s"):format(status.state or "UNKNOWN"))
  print(("Uptime:      %d seconds"):format(math.floor(os.clock())))
  print(("Services:    %d/%d active, %d failed"):format(active,total,failed))
  print(("Processes:   %d"):format(#ctx.kernel.process.all()))
  print(("Peripherals: %d"):format((function() local n=0 for _ in pairs(ctx.kernel.device.devices or {}) do n=n+1 end return n end)()))
  print(("Address:     %s"):format(machine.address or "-"))
  print(("Manager:     %s"):format(machine.manager or "-"))
  print(("Peers:       %d"):format(#(net.peers or {})))
  print(("Update:      %s (%s%%)"):format(
    update.state or update.phase or "IDLE",
    tostring(update.percent or ((update.state=="CURRENT") and 100 or 0))
  ))
  print(("Installed:   %s"):format(short(update.current_commit or update.commit or update.build or update.version)))
  print(("Available:   %s"):format(short(update.target_commit or update.available_commit or update.manager_commit)))
  print(("Manager:     %s"):format(update.manager_state or (update.manager_id and ("ID "..tostring(update.manager_id))) or "-"))
  if update.current_action then
    print(("Working:     %s %s"):format(tostring(update.current_action),tostring(update.current_file or "")))
  end
  if update.last_result then print(("Last result: %s"):format(tostring(update.last_result))) end
  print(("Lamp:        %s / %s"):format(
    status.lamp_side or machine.status_light_side or "bottom",
    status.lamp_output and "ON" or "OFF"
  ))
  if tonumber(status.error_code or 0)>0 then
    print(("Fault code:  %s (%s)"):format(
      tostring(status.error_code),
      tostring(status.error_reason or "unspecified")
    ))
  else
    print("Fault code:  none")
  end

  if failed>0 then
    print("")
    print("Failed units:")
    for _,u in ipairs(ctx.kernel.services:list()) do
      if u.state=="failed" then print("  "..u.name) end
    end
  end

  return failed>0 and 1 or 0
end}
