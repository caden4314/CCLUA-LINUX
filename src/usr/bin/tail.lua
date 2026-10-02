return {main=function(ctx,args)
 local n=10;local file=nil;local i=1
 while i<=#args do if args[i]=="-n" and args[i+1] then n=tonumber(args[i+1]) or 10;i=i+2 else file=args[i];i=i+1 end end
 if not file then print("tail: missing file operand");return 1 end
 if file:sub(1,1)~="/" then file=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..file) end
 local h,e=ctx.kernel.vfs.open(file,"r");if not h then print("tail: "..file..": "..tostring(e));return 1 end
 local data=h.readAll and h.readAll() or "";if h.close then h.close()end
 local lines={};for line in (data.."\n"):gmatch("(.-)\n")do lines[#lines+1]=line end
 for j=math.max(1,#lines-n),#lines do print(lines[j]) end
 return 0
end}
