return {main=function(ctx,args)
 if #args==0 then print("cat: standard input mode is not implemented yet");return 1 end
 local rc=0
 for _,p in ipairs(args)do
  if p:sub(1,1)~="/" then p=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..p) end
  local h,err=ctx.kernel.vfs.open(p,"r")
  if not h then print("cat: "..p..": "..tostring(err));rc=1
  else local s=h.readAll and h.readAll() or nil;if s then write(s)end;if h.close then h.close()end end
 end
 return rc
end}
