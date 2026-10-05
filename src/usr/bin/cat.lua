local stdio=dofile("/usr/lib/cclua/stdio.lua")

return {main=function(ctx,args)
 if #args==0 then
  local data,err=stdio.read_all(ctx)
  if data==nil then stdio.errorln(ctx,"cat: "..tostring(err));return 1 end
  stdio.write(ctx,data)
  return 0
 end

 local rc=0
 for _,p in ipairs(args) do
  if p=="-" then
   local data,err=stdio.read_all(ctx)
   if data==nil then stdio.errorln(ctx,"cat: "..tostring(err));rc=1
   else stdio.write(ctx,data) end
  else
   if p:sub(1,1)~="/" then p=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..p) end
   local h,err=ctx.kernel.vfs.open(p,"r")
   if not h then stdio.errorln(ctx,"cat: "..p..": "..tostring(err));rc=1
   else
    local s=h.readAll and h.readAll() or ""
    if h.close then h.close() end
    stdio.write(ctx,s)
   end
  end
 end
 return rc
end}
