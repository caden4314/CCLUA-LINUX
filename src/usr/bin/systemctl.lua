return {main=function(ctx,args)
 local cmd=args[1] or "list-units"
 if cmd=="list-units" then
  print("UNIT                      LOAD   ACTIVE")
  for _,u in ipairs(ctx.kernel.services:list())do
   print(("%-25s loaded %-8s"):format(u.name,u.state))
  end
  return 0
 end
 local name=args[2]
 if not name then print("systemctl: missing unit name");return 1 end
 if cmd=="status" then
  local u=ctx.kernel.services:get(name)
  if not u then print("Unit "..name.." could not be found.");return 4 end
  print("● "..u.name.." - "..(u.description or ""))
  print("   Loaded: loaded; "..(u.enabled and "enabled" or "disabled"))
  print("   Active: "..u.state..(u.pid and (" (PID "..u.pid..")") or ""))
  if u.error then print("    Error: "..u.error)end
  return u.state=="active" and 0 or 3
 elseif cmd=="start" then local ok,e=ctx.kernel.services:start(name);if not ok then print("Failed to start "..name..": "..tostring(e));return 1 end;return 0
 elseif cmd=="stop" then local ok,e=ctx.kernel.services:stop(name);if not ok then print("Failed to stop "..name..": "..tostring(e));return 1 end;return 0
 elseif cmd=="restart" then local ok,e=ctx.kernel.services:restart(name);if not ok then print("Failed to restart "..name..": "..tostring(e));return 1 end;return 0
 elseif cmd=="enable" then local ok,e=ctx.kernel.services:enable(name);if not ok then print(tostring(e));return 1 end;return 0
 elseif cmd=="disable" then local ok,e=ctx.kernel.services:disable(name);if not ok then print(tostring(e));return 1 end;return 0
 else print("systemctl: unsupported verb: "..cmd);return 1 end
end}
