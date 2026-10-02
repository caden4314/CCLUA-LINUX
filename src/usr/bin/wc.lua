return {main=function(ctx,args)
 local file=args[#args];if not file then print("wc: missing file operand");return 1 end
 if file:sub(1,1)~="/" then file=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..file) end
 local h,e=ctx.kernel.vfs.open(file,"r");if not h then print("wc: "..file..": "..tostring(e));return 1 end
 local data=h.readAll and h.readAll() or "";if h.close then h.close()end
 local lines=0;for _ in data:gmatch("\n")do lines=lines+1 end
 local words=0;for _ in data:gmatch("%S+")do words=words+1 end
 print(("%d %d %d %s"):format(lines,words,#data,file));return 0
end}
