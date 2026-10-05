local stdio=dofile("/usr/lib/cclua/stdio.lua")

local function read_source(ctx,file)
 if not file or file=="-" then return stdio.read_all(ctx) end
 if file:sub(1,1)~="/" then file=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..file) end
 local h,e=ctx.kernel.vfs.open(file,"r")
 if not h then return nil,e end
 local data=h.readAll and h.readAll() or ""
 if h.close then h.close() end
 return data
end

return {main=function(ctx,args)
 local n=10
 local file=nil
 local i=1
 while i<=#args do
  if args[i]=="-n" and args[i+1] then
   n=tonumber(args[i+1]) or 10;i=i+2
  else
   file=args[i];i=i+1
  end
 end
 local data,e=read_source(ctx,file)
 if data==nil then stdio.errorln(ctx,"head: "..tostring(e));return 1 end
 local c=0
 for line in (data.."\n"):gmatch("(.-)\n") do
  if c>=n then break end
  print(line)
  c=c+1
 end
 return 0
end}
