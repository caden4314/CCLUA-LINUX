local config=dofile("/usr/lib/cclua/config.lua")
local native=dofile("/usr/lib/cclua/native.lua")
local drivers=dofile("/usr/lib/cclua/drivers.lua")

local function read(path)
  return config.read_json(path,{}) or {}
end

local function count_devices(ctx)
  local n=0
  for _ in pairs(ctx.kernel.device.devices or {}) do n=n+1 end
  return n
end

local function collect(ctx)
  local machine=config.machine()
  local post=read("/var/lib/cclua/post.json")
  local network=read("/var/lib/cclua/network-health.json")
  local status=read("/var/lib/cclua/status.json")
  local update=read("/var/lib/cclua/update-state.json")
  local session=read("/var/lib/cclua/session-health.json")
  local apphost=read("/var/lib/cclua/apphost.json")
  local driverState=read("/var/lib/cclua/drivers.json")

  local services={}
  local failed={}
  local restarts=0
  for _,u in ipairs(ctx.kernel.services:list()) do
    if not u.reference or u.exec then
      services[#services+1]={
        name=u.name,state=u.state,pid=u.pid,
        error=u.error,restart_count=u.restart_count or 0,
        total_restarts=u.total_restarts or 0,
      }
      restarts=restarts+(tonumber(u.total_restarts) or 0)
      if u.state=="failed" then failed[#failed+1]=u.name end
    end
  end

  local problems={}
  local warnings={}
  if post.fatal==true or tostring(post.state):upper()=="FAILED" then
    problems[#problems+1]="fatal POST failure"
  elseif tostring(post.state):upper()=="DEGRADED" then
    problems[#problems+1]="POST warnings present"
  end

  local netState=tostring(network.state or "UNKNOWN"):upper()
  if machine.role~="manager" and machine.role~="network-manager"
    and netState~="ONLINE" and netState~="CHECKING" then
    problems[#problems+1]="network link "..netState:lower()
  end
  if #failed>0 then problems[#problems+1]=#failed.." failed service(s)" end
  if tostring(update.state or ""):upper()=="FAILED" then problems[#problems+1]="update failed" end
  if session.recovery==true then problems[#problems+1]="session is in recovery mode" end

  local nativeInfo=drivers.native()
  if not nativeInfo.available then
    warnings[#warnings+1]="CCPerf native runtime unavailable; using stock compatibility paths"
  end

  local incompatibleApps={}
  for _,app in ipairs(apphost.apps or {}) do
    if app.compatible==false then incompatibleApps[#incompatibleApps+1]=app.name end
  end
  if #incompatibleApps>0 then
    warnings[#warnings+1]=#incompatibleApps.." hosted app(s) have unsatisfied role/capability requirements"
  end

  local driverCaps=driverState.capabilities or {}
  if #driverCaps==0 and count_devices(ctx)>0 then
    warnings[#warnings+1]="driver capability inventory has not been published yet"
  end

  return {
    schema=1,
    hostname=machine.hostname,
    role=machine.role,
    computer_id=os.getComputerID(),
    system_state=status.state,
    post=post,
    network=network,
    update=update,
    session=session,
    services=services,
    failed_services=failed,
    service_restarts=restarts,
    peripherals=count_devices(ctx),
    native=nativeInfo,
    drivers={
      devices=driverState.devices or {},
      capabilities=driverCaps,
    },
    apps={
      total=#(apphost.apps or {}),
      incompatible=incompatibleApps,
    },
    warnings=warnings,
    problems=problems,
    healthy=#problems==0,
  }
end

local function short(value,n)
  local s=tostring(value or "-")
  n=n or 24
  if #s<=n then return s end
  return s:sub(1,n-1).."~"
end

local function display(data)
  print("CCLUA Doctor")
  print("============")
  print(("Host:        %s (ID %s)"):format(data.hostname or "-",data.computer_id or "-"))
  print(("Role:        %s"):format(data.role or "-"))
  print(("System:      %s"):format(data.system_state or "UNKNOWN"))
  print(("POST:        %s (%s pass / %s warn / %s fail)"):format(
    data.post.state or "UNKNOWN",data.post.pass or 0,data.post.warn or 0,data.post.fail or 0
  ))
  print(("Network:     %s  RTT %sms  missed %s"):format(
    data.network.state or "UNKNOWN",
    tostring(data.network.manager_rtt_ms or "-"),
    tostring(data.network.missed_probes or 0)
  ))
  print(("Modems:      %s"):format(data.network.modem_count or 0))
  print(("Peripherals: %s"):format(data.peripherals or 0))
  print(("Drivers:     %d devices / %d capabilities"):format(
    #(data.drivers and data.drivers.devices or {}),
    #(data.drivers and data.drivers.capabilities or {})
  ))
  print(("Native:      %s %s"):format(
    data.native and data.native.available and "CCPerf" or "stock",
    tostring(data.native and data.native.version or "")
  ))
  print(("Apps:        %d total / %d incompatible"):format(
    data.apps and data.apps.total or 0,
    #(data.apps and data.apps.incompatible or {})
  ))
  print(("Services:    %d total / %d failed / %d restarts"):format(
    #(data.services or {}),#(data.failed_services or {}),data.service_restarts or 0
  ))
  print(("Update:      %s -> %s"):format(
    short(data.update.current_commit or "-",12),
    short(data.update.available_commit or data.update.target_commit or "-",12)
  ))
  print(("Session:     %s%s"):format(
    data.session.mode or "-",
    data.session.recovery and " (RECOVERY)" or ""
  ))

  if #(data.warnings or {})>0 then
    term.setTextColor(colors.yellow)
    print("")
    print("Warnings:")
    for _,warning in ipairs(data.warnings) do print("  - "..warning) end
    term.setTextColor(colors.white)
  end

  if #(data.problems or {})==0 then
    term.setTextColor(colors.lime)
    print("")
    print("No problems detected.")
    term.setTextColor(colors.white)
  else
    term.setTextColor(colors.yellow)
    print("")
    print("Problems:")
    for _,problem in ipairs(data.problems) do print("  - "..problem) end
    term.setTextColor(colors.white)
  end

  if #(data.failed_services or {})>0 then
    print("")
    print("Failed services:")
    for _,name in ipairs(data.failed_services) do
      local u=nil
      for _,row in ipairs(data.services) do if row.name==name then u=row break end end
      print(("  %-30s %s"):format(name,short(u and u.error or "failed",40)))
    end
  end
end

return {main=function(ctx,args)
  local cmd=tostring(args[1] or "status"):lower()

  if cmd=="repair" then
    print("Running safe CCLUA repairs...")
    ctx.kernel.device.scan(ctx.kernel)
    ctx.kernel.device.snapshot()
    print("[ OK ] Peripheral inventory rescanned")

    local net=dofile("/usr/lib/cclua/net.lua")
    local opened=net.open_management_modems()
    print(("[ OK ] Management modems reopened: %d"):format(#opened))

    local restarted=0
    for _,u in ipairs(ctx.kernel.services:list()) do
      if u.state=="failed" and u.enabled and type(u.exec)=="function" then
        local ok,err=ctx.kernel.services:restart(u.name)
        if ok then
          print("[ OK ] Restarted "..u.name)
          restarted=restarted+1
        else
          term.setTextColor(colors.red)
          print("[FAIL] "..u.name..": "..tostring(err))
          term.setTextColor(colors.white)
        end
      end
    end
    if restarted==0 then print("[ OK ] No failed enabled services needed restart") end
    print("")
  elseif cmd=="json" then
    print(textutils.serializeJSON(collect(ctx)))
    return 0
  elseif cmd~="status" then
    print("Usage: cclua-doctor [status|repair|json]")
    return 1
  end

  local data=collect(ctx)
  display(data)
  return data.healthy and 0 or 1
end}
