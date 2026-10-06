local api=dofile("/usr/lib/cclua/api/system.lua")
local drivers=dofile("/usr/lib/cclua/drivers.lua")
local pkgdb=dofile("/usr/lib/cclua/package_db.lua")

local function usage()
  print("Usage: cclua <status|services|network|update|apps|native|drivers|capabilities|packages|api> [--json]")
  print("       cclua services [failed|active]")
end

local function short(value,n)
  local s=tostring(value or "-")
  n=tonumber(n) or 16
  return #s>n and s:sub(1,n) or s
end

local function has_flag(args,flag)
  for _,value in ipairs(args or {}) do if value==flag then return true end end
  return false
end

local function json(value)
  if not textutils or not textutils.serializeJSON then
    print("cclua: JSON encoder unavailable")
    return 1
  end
  print(textutils.serializeJSON(value))
  return 0
end

local function print_status(s)
  print(("%s (ID %s)  %s"):format(s.host.hostname,s.host.computer_id,s.host.role))
  print(("System   %-10s  POST %-8s  uptime %ss"):format(
    s.system.state,s.post.state,s.system.uptime_seconds))
  print(("Services %d/%d active  %d failed  %d restarts"):format(
    s.system.services.active,s.system.services.total,
    s.system.services.failed,s.system.services.restarts))
  print(("Runtime  %d processes  %d peripherals"):format(
    s.system.process_count,s.system.peripheral_count))
  print(("Network  %-10s  %s  RTT %sms  %d peers"):format(
    s.network.state,tostring(s.network.address or "-"),
    tostring(s.network.manager_rtt_ms or "-"),s.network.peer_count))
  print(("Update   %-10s  %3d%%  %s"):format(
    s.update.state,s.update.percent,short(s.update.current_commit,16)))
end
local function print_services(s,filter)
  print(("SERVICES  %d active / %d total / %d failed"):format(
    s.system.services.active,s.system.services.total,s.system.services.failed))
  for _,unit in ipairs(s.services or {}) do
    if not filter or unit.state==filter then
      local marker=unit.state=="active" and "+" or unit.state=="failed" and "!" or "-"
      local suffix=unit.error and ("  "..tostring(unit.error)) or ""
      print((" %s %-34s %-9s pid=%s%s"):format(
        marker,tostring(unit.name or "-"),tostring(unit.state or "-"),
        tostring(unit.pid or "-"),suffix))
    end
  end
end

local function print_network(s)
  print("NETWORK")
  print(("State:    %s"):format(s.network.state))
  print(("Address:  %s"):format(tostring(s.network.address or "-")))
  print(("Manager:  %s  ID %s"):format(
    tostring(s.network.manager or "-"),tostring(s.network.manager_id or "-")))
  print(("RTT:      %s ms"):format(tostring(s.network.manager_rtt_ms or "-")))
  print(("Modems:   %d  missed=%d  reopens=%d"):format(
    s.network.modem_count,s.network.missed_probes,s.network.reopen_count))
  print(("Peers:    %d"):format(s.network.peer_count))
end

local function print_update(s)
  print("UPDATE")
  print(("State:      %s (%d%%)"):format(s.update.state,s.update.percent))
  print(("Installed:  %s"):format(short(s.update.current_commit,32)))
  print(("Available:  %s"):format(short(s.update.available_commit,32)))
  print(("Manager:    %s"):format(tostring(s.update.manager_state or "-")))
  print(("Auto apply: %s"):format(s.update.auto_apply and "enabled" or "disabled"))
  if s.update.current_action then
    print(("Working:    %s %s"):format(s.update.current_action,tostring(s.update.current_file or "")))
  end
  if s.update.last_result then print("Last:       "..tostring(s.update.last_result)) end
end
local function print_apps(s)
  local apps=s.apps and s.apps.items or {}
  print(("APPS  host=%s  count=%d"):format(
    tostring(s.apps and s.apps.hostname or s.host.hostname),#apps))
  if #apps==0 then print("  (no hosted apps reported)") return end
  for _,app in ipairs(apps) do
    local compat=app.compatible==false and " !incompatible" or ""
    print(("  %-24s %-9s pid=%s  version=%s%s"):format(
      tostring(app.name or "-"),tostring(app.state or "-"),
      tostring(app.pid or "-"),tostring(app.version or "-"),compat))
  end
end

local function print_native(s)
  print("NATIVE RUNTIME")
  print("Available: "..tostring(s.native and s.native.available==true))
  print("Version:   "..tostring(s.native and s.native.version or "-"))
  local caps=s.native and s.native.capabilities or {}
  for k,v in pairs(caps) do
    print(("  %-28s %s"):format(tostring(k),tostring(v)))
  end
end

local function print_drivers()
  local rows=drivers.scan()
  print(("DRIVERS  %d devices"):format(#rows))
  for _,d in ipairs(rows) do
    print(("  %-18s %-20s %-10s"):format(d.name,d.driver,d.class))
  end
end

local function print_capabilities()
  local caps,providers=drivers.capabilities()
  print(("CAPABILITIES  %d"):format(#caps))
  for _,cap in ipairs(caps) do
    print(("  %-30s %s"):format(cap,table.concat(providers[cap] or {},", ")))
  end
end

local function print_packages()
  local meta=pkgdb.load()
  print(("PACKAGES  %d native implementations / %d Ubuntu reference entries"):format(
    meta.implemented_count or 0,meta.reference_count or 0))
  for _,p in ipairs(pkgdb.implemented()) do
    print(("  %-24s %-18s %s"):format(
      p.name,tostring(p.version or "-"),table.concat(p.commands or {},", ")))
  end
end

return {main=function(ctx,args)
  args=args or {}
  local command=args[1] or "status"
  if command=="help" or command=="--help" or command=="-h" then usage();return 0 end

  local snapshot=api.snapshot(ctx)
  if command=="api" or has_flag(args,"--json") then return json(snapshot) end

  if command=="status" then
    print_status(snapshot)
  elseif command=="services" then
    local filter=args[2]
    if filter~="failed" and filter~="active" then filter=nil end
    print_services(snapshot,filter)
  elseif command=="network" then
    print_network(snapshot)
  elseif command=="update" then
    print_update(snapshot)
  elseif command=="apps" then
    print_apps(snapshot)
  elseif command=="native" then
    print_native(snapshot)
  elseif command=="drivers" then
    print_drivers()
  elseif command=="capabilities" then
    print_capabilities()
  elseif command=="packages" then
    print_packages()
  else
    usage()
    return 2
  end

  return snapshot.system.error_code>0 and 1 or 0
end}
