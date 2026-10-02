local shell=dofile("/usr/lib/cclua/shell.lua")
return {main=function(ctx,args)
 local name=args[1] or "root"
 local u=ctx.kernel.users.by_name(name)
 if not u then print("su: user "..name.." does not exist");return 1 end
 if ctx.process.uid~=0 and ctx.process.uid~=u.uid then
  print("su: Authentication failure")
  return 1
 end
 local olduid,oldgid,oldcwd=ctx.process.uid,ctx.process.gid,ctx.process.cwd
 ctx.process.uid=u.uid;ctx.process.gid=u.gid;ctx.process.cwd=u.home or "/"
 local oldhome=ctx.process.environment.HOME
 ctx.process.environment.HOME=u.home or "/"
 local rc=shell.run(ctx,{"--login"})
 ctx.process.uid=olduid;ctx.process.gid=oldgid;ctx.process.cwd=oldcwd;ctx.process.environment.HOME=oldhome
 return rc
end}
