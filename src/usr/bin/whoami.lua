return {main=function(ctx,args)
 local u=ctx.kernel.users.by_uid(ctx.process.uid)
 print((u and u.name) or tostring(ctx.process.uid))
 return 0
end}
