return {main=function(ctx,args)
 if ctx.process.uid~=0 then print("groupadd: Permission denied.");return 1 end
 local gid=nil;local name=nil;local i=1
 while i<=#args do if args[i]=="-g" and args[i+1] then gid=tonumber(args[i+1]);i=i+2 else name=args[i];i=i+1 end end
 if not name then print("groupadd: missing group name");return 2 end
 local g,e=ctx.kernel.users.add_group(name,gid)
 if not g then print("groupadd: "..tostring(e));return 9 end
 return 0
end}
