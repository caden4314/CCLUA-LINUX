return {main=function(ctx,args)
 local file=args[1];if not file then print("more: missing file");return 1 end
 if file:sub(1,1)~="/" then file=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..file)end
 local h,e=ctx.kernel.vfs.open(file,"r");if not h then print("more: "..tostring(e));return 1 end
 local _,height=term.getSize();local row=0
 while true do
  local line=h.readLine and h.readLine() or nil;if not line then break end
  print(line);row=row+1
  if row>=height-2 then term.setTextColor(colors.yellow);write("--More--");term.setTextColor(colors.white);read();row=0 end
 end
 if h.close then h.close()end
 return 0
end}
