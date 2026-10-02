return {main=function(ctx,args)
 local prog=args[1];local file=args[2]
 if not prog then print("awk: missing program");return 2 end
 local field=prog:match("{%s*print%s+%$(%d+)%s*}") or prog:match("{print%s+%$(%d+)}")
 local print0=prog:match("{%s*print%s*}")~=nil
 if not field and not print0 then print("awk: CCLUA 0.2 supports only '{print}' and '{print $N}'");return 2 end
 local function run(data)
  for line in (data.."\n"):gmatch("(.-)\n")do
   if print0 then print(line)
   else local f={};for x in line:gmatch("%S+")do f[#f+1]=x end;print(f[tonumber(field)] or "")end
  end
 end
 if file then
  if file:sub(1,1)~="/" then file=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..file)end
  local h,e=ctx.kernel.vfs.open(file,"r");if not h then print("awk: "..tostring(e));return 2 end
  local d=h.readAll and h.readAll() or "";if h.close then h.close()end;run(d)
 else local l=read();if l then run(l)end end
 return 0
end}
