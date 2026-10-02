return {main=function(ctx,args)
 local entries=ctx.kernel.log.entries()
 for _,e in ipairs(entries)do
  local ts=tostring(e.timestamp or 0)
  local pid=e.pid and ("["..e.pid.."]") or ""
  print(("%s %-7s %-10s%s: %s"):format(ts,e.level or "info",e.subsystem or "kernel",pid,e.message or ""))
 end
 return 0
end}
