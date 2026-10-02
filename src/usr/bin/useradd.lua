return {main=function(ctx,args)
 if ctx.process.uid~=0 then print("useradd: Permission denied.");return 1 end
 local create_home=true;local shell=nil;local uid=nil;local gid=nil;local home=nil;local user=nil;local i=1
 while i<=#args do
  local a=args[i]
  if a=="-M" then create_home=false;i=i+1
  elseif a=="-m" then create_home=true;i=i+1
  elseif a=="-s" and args[i+1] then shell=args[i+1];i=i+2
  elseif a=="-u" and args[i+1] then uid=tonumber(args[i+1]);i=i+2
  elseif a=="-g" and args[i+1] then gid=tonumber(args[i+1]);i=i+2
  elseif a=="-d" and args[i+1] then home=args[i+1];i=i+2
  else user=a;i=i+1 end
 end
 if not user then print("useradd: missing user name");return 2 end
 local u,e=ctx.kernel.users.add_user(user,{uid=uid,gid=gid,home=home,shell=shell,create_home=create_home})
 if not u then print("useradd: "..tostring(e));return 9 end
 return 0
end}
