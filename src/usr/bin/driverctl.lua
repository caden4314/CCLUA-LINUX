local drivers=dofile("/usr/lib/cclua/drivers.lua")

local function usage()
  print("Usage:")
  print("  driverctl list")
  print("  driverctl show <device>")
  print("  driverctl caps")
  print("  driverctl find <capability>")
  print("  driverctl native")
end

local function join(t,sep)
  return table.concat(t or {},sep or ", ")
end

return {main=function(ctx,args)
  local op=tostring(args[1] or "list"):lower()

  if op=="list" then
    local rows=drivers.scan()
    if #rows==0 then print("(no peripherals)");return 0 end
    for _,d in ipairs(rows) do
      print(("%-18s %-18s %-10s %s"):format(
        d.name,d.driver,d.class,join(d.types,"+")))
    end
    return 0
  elseif op=="show" then
    local d,err=drivers.describe(args[2])
    if not d then print(err);return 1 end
    print("Device: "..d.name)
    print("Driver: "..d.driver.." v"..tostring(d.driver_version))
    print("Class:  "..d.class)
    print("Types:  "..join(d.types))
    print("Capabilities:")
    for _,cap in ipairs(d.capabilities or {}) do print("  "..cap) end
    print("Methods:")
    for _,m in ipairs(d.methods or {}) do print("  "..m) end
    return 0
  elseif op=="caps" then
    local caps,providers=drivers.capabilities()
    for _,cap in ipairs(caps) do
      print(("%-28s %s"):format(cap,join(providers[cap])))
    end
    return 0
  elseif op=="find" then
    local cap=tostring(args[2] or "")
    if cap=="" then usage();return 1 end
    local found=drivers.find(cap)
    if #found==0 then print("No provider for "..cap);return 1 end
    for _,d in ipairs(found) do print(d.name.."  "..d.driver) end
    return 0
  elseif op=="native" then
    local n=drivers.native()
    print("Native runtime: "..(n.available and "available" or "unavailable"))
    print("Driver: "..n.driver.." v"..tostring(n.driver_version))
    print("Version: "..tostring(n.version or "-"))
    for _,cap in ipairs(n.capabilities or {}) do print("  "..cap) end
    return 0
  end

  usage()
  return 1
end}
