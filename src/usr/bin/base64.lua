return {main=function(ctx,args)
 local decode=false;local file=nil
 for _,a in ipairs(args)do if a=="-d" or a=="--decode" then decode=true else file=a end end
 local data=""
 if file then
  if file:sub(1,1)~="/" then file=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..file)end
  local h,e=ctx.kernel.vfs.open(file,"r");if not h then print("base64: "..tostring(e));return 1 end
  data=h.readAll and h.readAll() or "";if h.close then h.close()end
 else local l=read();data=l or "" end
 if decode then
  if not textutils.decodeBase64 then print("base64: decoder unavailable");return 1 end
  local ok,res=pcall(textutils.decodeBase64,data:gsub("%s",""));if not ok then print("base64: invalid input");return 1 end
  write(res)
 else
  if not textutils.encodeBase64 then print("base64: encoder unavailable");return 1 end
  print(textutils.encodeBase64(data))
 end
 return 0
end}
