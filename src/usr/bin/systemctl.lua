local ui=dofile("/usr/lib/cclua/cli_ui.lua")

local function unit_color(state)
  return ui.state_color(state)
end

local function print_unit_row(unit)
  local sub=(unit.state=="active" and "running") or unit.state
  local name=tostring(unit.name or "?")
  local state=tostring(unit.state or "unknown")
  write(("%-32s loaded "):format(name:sub(1,32)))
  term.setTextColor(unit_color(state))
  write(("%-11s"):format(state))
  term.setTextColor(colors.lightGray)
  print(" "..tostring(sub))
  term.setTextColor(colors.white)
end

local function error(message,hint,code)
  ui.error(message,hint)
  return code or 1
end

return {main=function(ctx,args)
  local cmd=args[1] or "list-units"

  if cmd=="list-units" or cmd=="--failed" then
    local failedOnly=cmd=="--failed" or args[2]=="--failed"
    ui.table_header("UNIT                             LOAD   ACTIVE      SUB")
    local shown=0
    for _,unit in ipairs(ctx.kernel.services:list()) do
      local visible
      if failedOnly then
        visible=unit.state=="failed"
      else
        visible=unit.state=="active" or (not unit.reference and unit.state~="inactive")
      end
      if visible then print_unit_row(unit);shown=shown+1 end
    end
    print("")
    ui.dim(("%d loaded unit%s listed."):format(shown,shown==1 and "" or "s"))
    return 0

  elseif cmd=="is-system-running" then
    local failed,starting=0,0
    for _,unit in ipairs(ctx.kernel.services:list()) do
      if not unit.reference or unit.exec then
        if unit.state=="failed" then failed=failed+1 end
        if unit.state=="activating" then starting=starting+1 end
      end
    end
    if failed>0 then term.setTextColor(colors.red);print("degraded");ui.reset();return 1 end
    if starting>0 or os.clock()<4 then term.setTextColor(colors.yellow);print("starting");ui.reset();return 1 end
    term.setTextColor(colors.lime);print("running");ui.reset();return 0

  elseif cmd=="list-unit-files" then
    ui.table_header("UNIT FILE                        STATE       PRESET")
    for _,unit in ipairs(ctx.kernel.services:list()) do
      local state=unit.enabled and "enabled" or "disabled"
      if unit.reference and not unit.exec then state="static" end
      write(("%-32s "):format(unit.name:sub(1,32)))
      term.setTextColor(unit_color(state=="enabled" and "active" or state))
      write(("%-11s"):format(state))
      term.setTextColor(colors.lightGray)
      print(" enabled")
      term.setTextColor(colors.white)
    end
    return 0
  end

  local name=args[2]
  if not name then
    return error("systemctl "..cmd..": missing unit name",
      "Example: systemctl "..cmd.." systemd-networkd.service",1)
  end
  local unit=ctx.kernel.services:get(name)

  if cmd=="status" then
    if not unit then return error("Unit "..name.." could not be found.","Run 'systemctl list-units' to see loaded units.",4) end
    local mark=unit.state=="active" and "*" or (unit.state=="failed" and "!" or "-")
    term.setTextColor(unit_color(unit.state))
    write(mark.." ")
    term.setTextColor(colors.white)
    print(unit.name.." - "..tostring(unit.description or ""))

    local source=(unit.ubuntu and unit.ubuntu.source_path) or "/usr/lib/systemd/system/"..unit.name
    ui.label("Loaded","loaded ("..source.."; "..(unit.enabled and "enabled" or "disabled")..")")
    ui.status("Active",unit.state,unit.pid and ("PID "..unit.pid) or nil)
    if unit.total_restarts and tonumber(unit.total_restarts)>0 then
      ui.label("Restarts",unit.total_restarts)
    end
    if unit.reference and not unit.exec then
      ui.warning("Ubuntu reference unit; native CCLUA service body is not implemented.")
    end
    if unit.ubuntu then
      if unit.ubuntu.after then ui.label("After",unit.ubuntu.after) end
      if unit.ubuntu.wants then ui.label("Wants",unit.ubuntu.wants) end
      if unit.ubuntu.requires then ui.label("Requires",unit.ubuntu.requires) end
      if unit.ubuntu.exec_start then ui.label("ExecStart",unit.ubuntu.exec_start) end
    end
    if unit.error then
      print("")
      ui.error(tostring(unit.error),"Try 'journalctl -u "..unit.name.."' for related logs.")
    end
    return unit.state=="active" and 0 or 3

  elseif cmd=="cat" then
    if not unit then return error("No files found for "..name..".",nil,1) end
    ui.dim("# "..((unit.ubuntu and unit.ubuntu.source_path) or ("/usr/lib/systemd/system/"..unit.name)))
    print("[Unit]")
    if unit.description then print("Description="..unit.description) end
    if unit.ubuntu and unit.ubuntu.after then print("After="..unit.ubuntu.after) end
    if unit.ubuntu and unit.ubuntu.wants then print("Wants="..unit.ubuntu.wants) end
    print("")
    print("[Service]")
    if unit.ubuntu and unit.ubuntu.type then print("Type="..unit.ubuntu.type) end
    if unit.ubuntu and unit.ubuntu.exec_start then print("ExecStart="..unit.ubuntu.exec_start) end
    return 0
  elseif cmd=="is-active" then
    if unit and unit.state=="active" then print("active");return 0 end
    print(unit and tostring(unit.state or "inactive") or "inactive")
    return 3

  elseif cmd=="is-enabled" then
    if not unit then print("not-found");return 1 end
    if unit.reference and not unit.exec then print("static");return 0 end
    print(unit.enabled and "enabled" or "disabled")
    return unit.enabled and 0 or 1

  elseif cmd=="start" then
    if not unit then return error("Failed to start "..name..": Unit not found.","Run 'systemctl list-unit-files'.",5) end
    if unit.reference and not unit.exec then
      return error("Failed to start "..unit.name..": native CCLUA implementation is not available yet.",nil,1)
    end
    local ok,e=ctx.kernel.services:start(name)
    if not ok then return error("Failed to start "..name..": "..tostring(e),"Check 'systemctl status "..name.."'.",1) end
    return 0

  elseif cmd=="stop" then
    local ok,e=ctx.kernel.services:stop(name)
    if not ok then return error("Failed to stop "..name..": "..tostring(e),nil,1) end
    return 0

  elseif cmd=="restart" then
    local ok,e=ctx.kernel.services:restart(name)
    if not ok then return error("Failed to restart "..name..": "..tostring(e),"Check 'systemctl status "..name.."'.",1) end
    return 0
  elseif cmd=="enable" then
    local ok,e=ctx.kernel.services:enable(name)
    if not ok then return error(tostring(e),nil,1) end
    return 0

  elseif cmd=="disable" then
    local ok,e=ctx.kernel.services:disable(name)
    if not ok then return error(tostring(e),nil,1) end
    return 0
  end

  return error("Unsupported systemctl verb: "..tostring(cmd),
    "Supported: list-units, status, start, stop, restart, enable, disable, is-active, is-enabled, cat.",1)
end}
