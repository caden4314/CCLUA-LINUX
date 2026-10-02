return {main=function(ctx,args)
  local cmd=args[1] or "list-units"

  if cmd=="list-units" then
    print("UNIT                             LOAD   ACTIVE      SUB")
    for _,u in ipairs(ctx.kernel.services:list()) do
      if u.state=="active" or (not u.reference and u.state~="inactive") then
        local sub=(u.state=="active" and "running") or u.state
        print(("%-32s loaded %-11s %s"):format(u.name,u.state,sub))
      end
    end
    return 0
  elseif cmd=="list-unit-files" then
    print("UNIT FILE                        STATE       PRESET")
    for _,u in ipairs(ctx.kernel.services:list()) do
      local state=u.enabled and "enabled" or "disabled"
      if u.reference and not u.exec then state="static" end
      print(("%-32s %-11s enabled"):format(u.name,state))
    end
    return 0
  end

  local name=args[2]
  if not name then print("systemctl: missing unit name");return 1 end
  local u=ctx.kernel.services:get(name)

  if cmd=="status" then
    if not u then print("Unit "..name.." could not be found.");return 4 end
    local mark=u.state=="active" and "[+]" or (u.state=="failed" and "[!]" or "[-]")
    print(mark.." "..u.name.." - "..(u.description or ""))
    local source=(u.ubuntu and u.ubuntu.source_path) or "/usr/lib/systemd/system/"..u.name
    print("     Loaded: loaded ("..source.."; "..(u.enabled and "enabled" or "disabled")..")")
    print("     Active: "..u.state..(u.pid and (" (PID "..u.pid..")") or ""))
    if u.reference and not u.exec then print("     CCLUA: Ubuntu reference unit; native service body not implemented yet") end
    if u.ubuntu then
      if u.ubuntu.after then print("      After: "..u.ubuntu.after) end
      if u.ubuntu.wants then print("      Wants: "..u.ubuntu.wants) end
      if u.ubuntu.requires then print("   Requires: "..u.ubuntu.requires) end
      if u.ubuntu.exec_start then print("  ExecStart: "..u.ubuntu.exec_start) end
    end
    if u.error then print("      Error: "..u.error) end
    return u.state=="active" and 0 or 3
  elseif cmd=="cat" then
    if not u then print("No files found for "..name..".");return 1 end
    print("# "..((u.ubuntu and u.ubuntu.source_path) or ("/usr/lib/systemd/system/"..u.name)))
    print("[Unit]")
    if u.description then print("Description="..u.description) end
    if u.ubuntu and u.ubuntu.after then print("After="..u.ubuntu.after) end
    if u.ubuntu and u.ubuntu.wants then print("Wants="..u.ubuntu.wants) end
    print("[Service]")
    if u.ubuntu and u.ubuntu.type then print("Type="..u.ubuntu.type) end
    if u.ubuntu and u.ubuntu.exec_start then print("ExecStart="..u.ubuntu.exec_start) end
    return 0
  elseif cmd=="is-active" then
    if u and u.state=="active" then print("active");return 0 end
    print("inactive");return 3
  elseif cmd=="is-enabled" then
    if not u then print("not-found");return 1 end
    if u.reference and not u.exec then print("static");return 0 end
    print(u.enabled and "enabled" or "disabled");return u.enabled and 0 or 1
  elseif cmd=="start" then
    if not u then print("Failed to start "..name..": Unit not found.");return 5 end
    if u.reference and not u.exec then print("Failed to start "..u.name..": native CCLUA implementation not available yet.");return 1 end
    local ok,e=ctx.kernel.services:start(name);if not ok then print("Failed to start "..name..": "..tostring(e));return 1 end;return 0
  elseif cmd=="stop" then local ok,e=ctx.kernel.services:stop(name);if not ok then print("Failed to stop "..name..": "..tostring(e));return 1 end;return 0
  elseif cmd=="restart" then local ok,e=ctx.kernel.services:restart(name);if not ok then print("Failed to restart "..name..": "..tostring(e));return 1 end;return 0
  elseif cmd=="enable" then local ok,e=ctx.kernel.services:enable(name);if not ok then print(tostring(e));return 1 end;return 0
  elseif cmd=="disable" then local ok,e=ctx.kernel.services:disable(name);if not ok then print(tostring(e));return 1 end;return 0
  else
    print("systemctl: unsupported verb: "..cmd);return 1
  end
end}
