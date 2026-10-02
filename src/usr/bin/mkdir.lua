return {main=function(ctx,args)
 local parents=false;local paths={}
 for _,a in ipairs(args)do if a=="-p" then parents=true else paths[#paths+1]=a end end
 if #paths==0 then print("mkdir: missing operand");return 1 end
 local rc=0
 for _,p in ipairs(paths)do
  if p:sub(1,1)~="/" then p=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..p) end
  local ok,err=ctx.kernel.vfs.mkdir(p)
  if not ok and not (parents and err=="EEXIST") then print("mkdir: cannot create directory '"..p.."': "..tostring(err));rc=1 end
 end
 return rc
end}
