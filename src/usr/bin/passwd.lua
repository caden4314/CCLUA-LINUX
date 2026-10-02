return {main=function(ctx,args)
 local name=args[1] or ((ctx.kernel.users.by_uid(ctx.process.uid) or {}).name)
 if not name or not ctx.kernel.users.by_name(name) then print("passwd: user does not exist");return 1 end
 if ctx.process.uid~=0 and name~=(ctx.kernel.users.by_uid(ctx.process.uid) or {}).name then print("passwd: Permission denied.");return 1 end
 print("passwd: password authentication backend is not enabled yet.")
 print("CCLUA accounts currently use local console identity; SSH will use keys.")
 return 1
end}
