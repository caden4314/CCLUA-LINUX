local config=dofile("/usr/lib/cclua/config.lua")
local net=dofile("/usr/lib/cclua/net.lua")
local protocol="cclua-lighting-v1"

local function usage()
  print("Usage:")
  print("  cclua-lightctl status")
  print("  cclua-lightctl discover")
  print("  cclua-lightctl on|off")
  print("  cclua-lightctl animate")
  print("  cclua-lightctl set <relay> <on|off> [side]")
end

local function bool(s)
  s=tostring(s or ""):lower()
  if s=="on" or s=="true" or s=="1" then return true end
  if s=="off" or s=="false" or s=="0" then return false end
  return nil
end

local function print_state(state)
  if type(state)~="table" then return end
  print(("Lighting node: %s (ID %s)"):format(state.hostname or "-",state.computer_id or "-"))
  print(("Healthy: %s   Desired: %s   Relays: %s"):format(
    tostring(state.healthy),state.desired_on and "ON" or "OFF",state.relay_count or 0
  ))
  if state.lever_enabled then
    print(("Lever: %s = %s"):format(state.lever_side or "-",state.lever_input and "ON" or "OFF"))
  end
  if state.animation_active then print("Animation: active") end
  if state.error then print("Error: "..tostring(state.error)) end
  for _,r in ipairs(state.relays or {}) do
    local active={}
    for side,v in pairs(r.outputs or {}) do if v then active[#active+1]=side end end
    table.sort(active)
    print(("  %-20s id=%-3s on=[%s]"):format(r.name or "-",r.id or "-",table.concat(active,",")))
  end
  if #(state.missing_relays or {})>0 then
    print("Missing: "..table.concat(state.missing_relays,", "))
  end
end

return {main=function(ctx,args)
  local machine=config.machine()
  local target=tonumber(machine.lighting_controller_id) or 3
  local cmd=args[1] or "status"
  local msg={protocol=protocol}

  if cmd=="status" or cmd=="discover" then
    msg.op=cmd
  elseif cmd=="on" or cmd=="off" then
    msg.op="all"
    msg.value=cmd=="on"
  elseif cmd=="animate" then
    msg.op="animate"
    msg.name=args[2] or "quick"
  elseif cmd=="set" then
    if not args[2] or not args[3] then usage();return 1 end
    local v=bool(args[3])
    if v==nil then usage();return 1 end
    msg.op="set";msg.relay=args[2];msg.value=v;msg.side=args[4]
  else
    usage();return 1
  end

  net.open_management_modems()
  local ok=rednet.send(target,msg,protocol)
  if not ok then print("Unable to send to lighting controller ID "..target);return 1 end
  local sender,res=rednet.receive(protocol,4)
  if not sender then print("Lighting controller did not respond.");return 1 end
  if sender~=target then print("Unexpected response from ID "..tostring(sender));return 1 end
  if type(res)~="table" then print("Invalid response.");return 1 end
  if not res.ok then print("Command failed: "..tostring(res.error));return 1 end
  print_state(res.state)
  return 0
end}
