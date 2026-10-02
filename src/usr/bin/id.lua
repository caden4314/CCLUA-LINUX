return {main=function(ctx,args)
 local target=ctx.process
 local u=ctx.kernel.users.by_uid(target.uid)
 local name=(u and u.name) or tostring(target.uid)
 local groups={target.gid}
 for _,g in ipairs(target.groups or {})do groups[#groups+1]=g end
 print(("uid=%d(%s) gid=%d(%s) groups=%s"):format(target.uid,name,target.gid,name,table.concat(groups,",")))
 return 0
end}
