local config=dofile("/usr/lib/cclua/config.lua")
local net=dofile("/usr/lib/cclua/net.lua")
local protocol="cclua-apphost-v1"

local function usage()
  print("Usage: cclua-appctl [status|list|start <app>|stop <app>|restart <app>]")
end

local function print_state(state)
  if type(state)~="table" then return end
  print(("App host: %s (ID %s)"):format(state.hostname or "-",state.computer_id or "-"))
  local apps=state.apps or {}
  if #apps==0 then print("(no apps installed)");return end
  for _,a in ipairs(apps) do
    print(("  %-24s %-8s pid=%s"):format(a.name or "-",a.state or "-",a.pid or "-"))
  end
end

return {main=function(ctx,args)
  local machine=config.machine()
  local target=tonumber(machine.app_server_id) or 2
  local cmd=args[1] or "status"
  local msg={protocol=protocol,op=cmd}

  if cmd=="start" or cmd=="stop" or cmd=="restart" then
    if not args[2] then usage();return 1 end
    msg.app=args[2]
  elseif cmd~="status" and cmd~="list" then
    usage();return 1
  end

  net.open_management_modems()
  local ok=rednet.send(target,msg,protocol)
  if not ok then print("Unable to send to app server ID "..target);return 1 end
  local sender,res=rednet.receive(protocol,3)
  if not sender then print("App server did not respond.");return 1 end
  if sender~=target then print("Unexpected response from ID "..tostring(sender));return 1 end
  if type(res)~="table" then print("Invalid response.");return 1 end
  if not res.ok then print("Command failed: "..tostring(res.error));return 1 end
  print_state(res.state)
  return 0
end}
