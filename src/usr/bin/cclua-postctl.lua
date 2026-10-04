local config=dofile("/usr/lib/cclua/config.lua")

local function print_result(data)
  if type(data)~="table" then
    print("No POST result is available.")
    return 1
  end

  print(("CCLUA POST: %s"):format(tostring(data.state or "UNKNOWN")))
  print(("Host: %s  Role: %s  ID: %s"):format(
    tostring(data.hostname or "-"),
    tostring(data.role or "-"),
    tostring(data.computer_id or "-")
  ))
  print(("Checks: %d pass, %d warn, %d fail, %d fatal"):format(
    tonumber(data.pass or 0),tonumber(data.warn or 0),
    tonumber(data.fail or 0),tonumber(data.fatal_count or 0)
  ))
  print("")
  for _,rec in ipairs(data.checks or {}) do
    local mark=rec.state=="PASS" and "[ OK ]" or rec.state=="WARN" and "[WARN]" or "[FAIL]"
    print(("%s %-22s %s"):format(mark,tostring(rec.label or rec.id),tostring(rec.detail or "")))
  end
  return data.fatal and 2 or data.degraded and 1 or 0
end

return {main=function(ctx,args)
  local cmd=tostring(args[1] or "status"):lower()
  if cmd=="run" or cmd=="rerun" then
    local post=dofile("/usr/lib/cclua/post.lua")
    local data=post.run(ctx,{animate=false})
    return data.fatal and 2 or data.degraded and 1 or 0
  elseif cmd=="status" or cmd=="show" then
    return print_result(config.read_json("/var/lib/cclua/post.json",nil))
  end

  print("Usage: cclua-postctl [status|run]")
  return 1
end}
