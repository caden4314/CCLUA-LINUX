return {main=function(ctx,args)
 local cap=fs.getCapacity and fs.getCapacity("/") or nil
 local free=fs.getFreeSpace("/")
 local total=cap or ((type(free)=="number" and free) or 0)
 local used=(type(total)=="number" and type(free)=="number") and math.max(0,total-free) or 0
 print("Filesystem        Size       Used      Avail Mounted on")
 print(("cclua-root %10s %10s %10s /"):format(tostring(total),tostring(used),tostring(free)))
 return 0
end}
