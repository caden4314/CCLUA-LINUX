return {main=function(ctx,args)
 local cmd=args[1] or "time"
 if cmd=="time" then
  print(("Startup finished in %.3fs (kernel) + %.3fs (userspace) = %.3fs"):format(0.05,math.min(os.clock(),1.0),math.min(os.clock()+0.05,1.05)))
  return 0
 elseif cmd=="blame" then
  for _,u in ipairs(ctx.kernel.services:list())do if u.state=="active" and not u.reference then print(("  10ms %s"):format(u.name))end end
  return 0
 end
 print("systemd-analyze: supported: time, blame");return 1
end}
