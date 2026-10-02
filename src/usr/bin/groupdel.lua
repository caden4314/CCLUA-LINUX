return {main=function(ctx,args)
 if ctx.process.uid~=0 then print("groupdel: Permission denied.");return 1 end
 if not args[1] then print("groupdel: missing group name");return 2 end
 local ok,e=ctx.kernel.users.delete_group(args[1])
 if not ok then print("groupdel: "..tostring(e));return 6 end
 return 0
end}
