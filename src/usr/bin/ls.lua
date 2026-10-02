local function join(a,b)if a=="/" then return "/"..b end return a.."/"..b end
return {main=function(ctx,args)
 local long=false;local all=false;local target=nil
 for _,a in ipairs(args)do
  if a:sub(1,1)=="-" then
   if a:find("l",2,true)then long=true end
   if a:find("a",2,true)then all=true end
  else target=a end
 end
 target=target or ctx.process.cwd
 if target:sub(1,1)~="/" then target=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..target) end
 if not ctx.kernel.vfs.exists(target) then print("ls: cannot access '"..target.."': No such file or directory");return 2 end
 if not ctx.kernel.vfs.isDir(target) then print(target:match("([^/]+)$") or target);return 0 end
 local list=ctx.kernel.vfs.list(target) or {};table.sort(list)
 for _,name in ipairs(list)do
  if all or name:sub(1,1)~="." then
   if long then
    local st=ctx.kernel.vfs.stat(join(target,name)) or {}
    print(("%s %8d %s"):format(st.isDir and "drwxr-xr-x" or "-rw-r--r--",st.size or 0,name))
   else print(name) end
  end
 end
 return 0
end}
