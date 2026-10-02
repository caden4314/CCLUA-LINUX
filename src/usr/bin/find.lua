local function walk(ctx,path,namepat)
 if not ctx.kernel.vfs.exists(path) then return end
 local base=path:match("([^/]+)$") or "/"
 if not namepat or base:match(namepat) then print(path) end
 if ctx.kernel.vfs.isDir(path) then
  for _,n in ipairs(ctx.kernel.vfs.list(path) or {})do
   local child=(path=="/") and ("/"..n) or (path.."/"..n)
   walk(ctx,child,namepat)
  end
 end
end
return {main=function(ctx,args)
 local start=ctx.process.cwd;local namepat=nil;local i=1
 if args[1] and args[1]:sub(1,1)~="-" then start=args[1];i=2 end
 while i<=#args do
  if args[i]=="-name" and args[i+1] then
   local glob=args[i+1]:gsub("([%^%$%(%)%%%.%[%]%+%-%?])","%%%1"):gsub("%*",".*")
   namepat="^"..glob.."$";i=i+2
  else i=i+1 end
 end
 if start:sub(1,1)~="/" then start=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..start) end
 walk(ctx,start,namepat);return 0
end}
