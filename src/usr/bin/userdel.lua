return {main=function(ctx,args)
 if ctx.process.uid~=0 then print("userdel: Permission denied.");return 1 end
 local remove=false;local user=nil
 for _,a in ipairs(args)do if a=="-r" then remove=true else user=a end end
 if not user then print("userdel: missing user name");return 2 end
 local ok,e=ctx.kernel.users.delete_user(user,remove)
 if not ok then print("userdel: "..tostring(e));return 6 end
 return 0
end}
