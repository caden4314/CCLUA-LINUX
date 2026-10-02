return {main=function(ctx,args)
 print("  PID  PPID USER       STAT COMMAND")
 for _,p in ipairs(ctx.kernel.process.all())do
  local u=ctx.kernel.users.by_uid(p.uid)
  local name=(u and u.name) or tostring(p.uid)
  print(("%5d %5d %-10s %-4s %s"):format(p.pid,p.ppid,name,p.state:sub(1,4),p.name))
 end
 return 0
end}
