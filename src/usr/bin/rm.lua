local function remove(ctx,path,recursive,force)
 if path:sub(1,1)~="/" then path=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..path) end
 if not ctx.kernel.vfs.exists(path) then if force then return true end return nil,"No such file or directory" end
 if ctx.kernel.vfs.isDir(path) and not recursive then return nil,"Is a directory" end
 if ctx.kernel.vfs.isDir(path) and recursive then
  for _,n in ipairs(ctx.kernel.vfs.list(path) or {})do local ok,e=remove(ctx,path.."/"..n,true,force);if not ok then return nil,e end end
 end
 return ctx.kernel.vfs.delete(path)
end
return {main=function(ctx,args)
 local recursive=false;local force=false;local paths={}
 for _,a in ipairs(args)do
  if a=="-r" or a=="-R" or a=="-rf" or a=="-fr" then recursive=true;if a:find("f")then force=true end
  elseif a=="-f" then force=true else paths[#paths+1]=a end
 end
 if #paths==0 then print("rm: missing operand");return 1 end
 local rc=0
 for _,p in ipairs(paths)do local ok,e=remove(ctx,p,recursive,force);if not ok then print("rm: cannot remove '"..p.."': "..tostring(e));rc=1 end end
 return rc
end}
