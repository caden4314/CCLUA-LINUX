local stdio=dofile("/usr/lib/cclua/stdio.lua")

local function scan(data,pattern)
 local found=false
 for line in (tostring(data or "").."\n"):gmatch("(.-)\n") do
  if line:find(pattern) then print(line);found=true end
 end
 return found
end

return {main=function(ctx,args)
 if #args<1 then stdio.errorln(ctx,"grep: usage: grep PATTERN [FILE...]");return 2 end
 local pattern=args[1]
 local rc=1

 if #args==1 then
  local data,err=stdio.read_all(ctx)
  if data==nil then stdio.errorln(ctx,"grep: "..tostring(err));return 2 end
  return scan(data,pattern) and 0 or 1
 end

 for i=2,#args do
  local p=args[i]
  if p=="-" then
   local data,err=stdio.read_all(ctx)
   if data==nil then stdio.errorln(ctx,"grep: "..tostring(err));rc=2
   elseif scan(data,pattern) then rc=0 end
  else
   if p:sub(1,1)~="/" then p=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..p) end
   local h,err=ctx.kernel.vfs.open(p,"r")
   if not h then stdio.errorln(ctx,"grep: "..p..": "..tostring(err));rc=2
   else
    local data=h.readAll and h.readAll() or ""
    if h.close then h.close() end
    if scan(data,pattern) then rc=0 end
   end
  end
 end
 return rc
end}
