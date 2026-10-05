local config=dofile("/usr/lib/cclua/config.lua")
local ui=dofile("/usr/lib/cclua/cli_ui.lua")

local function short(v)
  v=tostring(v or "-")
  if #v>12 then return v:sub(1,12) end
  return v
end

return {main=function(ctx,args)
  local plain=false
  for _,a in ipairs(args or {}) do if a=="--plain" or a=="--no-color" then plain=true end end

  local machine=config.machine()
  local status=config.read_json("/var/lib/cclua/status.json",{state="BOOTING"}) or {}
  local post=config.read_json("/var/lib/cclua/post.json",{state="UNKNOWN"}) or {}
  local link=config.read_json("/var/lib/cclua/network-health.json",{state="CHECKING"}) or {}
  local session=config.read_json("/var/lib/cclua/session-health.json",{}) or {}
  local update=config.read_json("/var/lib/cclua/update-state.json",{state="IDLE"}) or {}
  local net=config.read_json("/var/lib/cclua/network.json",{peers={},stats={}}) or {}

  local function heading(text)
    if plain then print(text) else ui.heading(text) end
  end
  local function label(name,value)
    if plain then print(("%-13s %s"):format(name..":",tostring(value or "-")))
    else ui.label(name,value) end
  end

  local function state(name,value,detail)
    if plain then
      print(("%-13s %s%s"):format(name..":",tostring(value or "UNKNOWN"),detail and ("  "..detail) or ""))
    else ui.status(name,value,detail) end
  end

  local active,failed,total=0,0,0
  local failedUnits={}
  for _,unit in ipairs(ctx.kernel.services:list()) do
    if not unit.reference or unit.exec then
      total=total+1
      if unit.state=="active" then active=active+1 end
      if unit.state=="failed" then
        failed=failed+1
        failedUnits[#failedUnits+1]=unit
      end
    end
  end

  local peripheralCount=0
  for _ in pairs(ctx.kernel.device.devices or {}) do peripheralCount=peripheralCount+1 end

  heading("CCLUA system status")
  label("Host",("%s  (ID %d)"):format(machine.hostname or "cclua-server",os.getComputerID()))
  label("Role",machine.role or "server")
  print("")
  heading("System")
  state("State",status.state or "BOOTING",status.error_reason)
  state("POST",post.state or "UNKNOWN",
    ("%s pass / %s warn / %s fail"):format(post.pass or 0,post.warn or 0,post.fail or 0))
  state("Services",failed>0 and "DEGRADED" or "HEALTHY",
    ("%d/%d active, %d failed, %s restarts"):format(active,total,failed,status.service_restarts or 0))
  label("Processes",#ctx.kernel.process.all())
  label("Session",(session.mode or "-")..(session.recovery and " (recovery)" or ""))
  label("Uptime",("%ds"):format(math.floor(os.clock())))
  label("Peripherals",peripheralCount)

  print("")
  heading("Network")
  label("Address",machine.address or "-")
  label("Manager",machine.manager or "-")
  state("Link",link.state or "CHECKING",
    ("RTT %sms, missed %s"):format(tostring(link.manager_rtt_ms or "-"),tostring(link.missed_probes or 0)))
  label("Modems",("%s  (reopens %s)"):format(tostring(link.modem_count or 0),tostring(link.reopen_count or 0)))
  label("Peers",#(net.peers or {}))
  print("")
  heading("Updates")
  local updateState=update.state or update.phase or "IDLE"
  state("State",updateState,(tostring(update.percent or (updateState=="CURRENT" and 100 or 0)).."%"))
  label("Installed",short(update.current_commit or update.commit or update.build or update.version))
  label("Available",short(update.target_commit or update.available_commit or update.manager_commit))
  label("Auto apply",update.auto_apply==false and "disabled" or "enabled")
  label("Manager",update.manager_state or (update.manager_id and ("ID "..tostring(update.manager_id))) or "-")
  if update.current_action then label("Working",tostring(update.current_action).." "..tostring(update.current_file or "")) end
  if update.last_result then label("Last result",update.last_result) end

  local faultCode=tonumber(status.error_code or 0) or 0
  if faultCode>0 or failed>0 then
    print("")
    heading("Attention")
    state("Fault",faultCode>0 and "FAULT" or "DEGRADED",
      faultCode>0 and ("code "..faultCode..": "..tostring(status.error_reason or "unspecified")) or nil)
    for _,unit in ipairs(failedUnits) do
      if plain then print("  failed  "..unit.name.."  "..tostring(unit.error or ""))
      else
        term.setTextColor(colors.red);write("  ! ");term.setTextColor(colors.white)
        print(unit.name..(unit.error and (" - "..tostring(unit.error)) or ""))
      end
    end
  end

  if not plain then ui.reset() end
  return (failed>0 or faultCode>0) and 1 or 0
end}
