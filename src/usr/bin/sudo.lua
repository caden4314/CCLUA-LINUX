local exec=dofile("/usr/lib/cclua/exec.lua")
return {main=function(ctx,args)
 if #args==0 then print("usage: sudo command [args...]");return 1 end
 local current=ctx.kernel.users.by_uid(ctx.process.uid)
 if ctx.process.uid~=0 and (not current or current.name~="caden") then
  print((current and current.name or tostring(ctx.process.uid)).." is not in the sudoers file.")
  return 1
 end
 return exec.run(ctx,args,{uid=0,gid=0,capabilities=ctx.kernel.capabilities.root()})
end}
