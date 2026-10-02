return {main=function(ctx,args)
 if #args<2 then print("grep: usage: grep PATTERN FILE...");return 2 end
 local pattern=args[1];local rc=1
 for i=2,#args do
  local p=args[i];if p:sub(1,1)~="/" then p=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..p) end
  local h,err=ctx.kernel.vfs.open(p,"r")
  if not h then print("grep: "..p..": "..tostring(err));rc=2
  else
   local data=h.readAll and h.readAll() or "";if h.close then h.close()end
   for line in (data.."\n"):gmatch("(.-)\n")do if line:find(pattern) then print(line);rc=0 end end
  end
 end
 return rc
end}
