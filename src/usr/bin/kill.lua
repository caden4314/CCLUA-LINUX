return {main=function(ctx,args)
 if #args==0 then print("kill: usage: kill [-SIGNAL] pid [...]");return 1 end
 local sig="TERM";local i=1
 if args[1]:sub(1,1)=="-" then sig=args[1]:sub(2);i=2 end
 local rc=0
 for n=i,#args do
  local pid=tonumber(args[n])
  if not pid then print("kill: "..args[n]..": invalid process id");rc=1
  else
   local ok,err=ctx.kernel.syscalls.kill(ctx.process,pid,sig)
   if not ok then print("kill: ("..pid..") - "..tostring(err));rc=1 end
  end
 end
 return rc
end}
