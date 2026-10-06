local config=dofile("/usr/lib/cclua/config.lua")
local test=dofile("/usr/lib/cclua/theater_selftest.lua")

local function print_report(r)
  print(("CCLUA THEATER A/V SELF TEST: %s"):format(tostring(r.state)))
  for _,c in ipairs(r.checks or {}) do
    local mark=c.state=="PASS" and "[ OK ]" or c.state=="WARN" and "[WARN]" or "[FAIL]"
    print(("%s %-8s %s"):format(mark,c.id,tostring(c.detail or "")))
  end
  print(("Summary: %d pass / %d warn / %d fail"):format(r.pass or 0,r.warn or 0,r.fail or 0))
end

return {main=function(ctx,args)
  local cmd=tostring(args[1] or "run"):lower()
  if cmd=="status" then
    local r=config.read_json("/var/lib/cclua/theater-selftest.json",nil)
    if not r then print("No theater A/V self-test result.");return 1 end
    print_report(r)
    return r.fail>0 and 2 or r.warn>0 and 1 or 0
  elseif cmd=="probe" then
    local q=test.quick(config.machine())
    print(textutils.serialize(q))
    return q.speakers==22 and q.monitor_present and 0 or 1
  elseif cmd=="run" then
    local r=test.run(ctx,{manual=true})
    print_report(r)
    return r.fail>0 and 2 or r.warn>0 and 1 or 0
  end
  print("Usage: cclua-avtest [run|status|probe]")
  return 1
end}
