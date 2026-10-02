return {main=function(ctx,args)
 local expr=nil;local files={};local i=1
 while i<=#args do
  if args[i]=="-e" and args[i+1] then expr=args[i+1];i=i+2
  elseif not expr and args[i]:sub(1,2)=="s/" then expr=args[i];i=i+1
  else files[#files+1]=args[i];i=i+1 end
 end
 if not expr then print("sed: missing script");return 1 end
 local delim=expr:sub(2,2)
 local pat,repl,flags=expr:match("^s(.)(.-)%1(.-)%1([g]*)$")
 if not pat then print("sed: unsupported script");return 1 end
 local function process(data)
  for line in (data.."\n"):gmatch("(.-)\n")do
   local out
   if flags=="g" then out=line:gsub(pat,repl)else out=line:gsub(pat,repl,1)end
   print(out)
  end
 end
 if #files==0 then local l=read();if l then process(l)end;return 0 end
 for _,file in ipairs(files)do
  local p=file;if p:sub(1,1)~="/" then p=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..p)end
  local h,e=ctx.kernel.vfs.open(p,"r");if not h then print("sed: "..tostring(e));return 2 end
  local d=h.readAll and h.readAll() or "";if h.close then h.close()end;process(d)
 end
 return 0
end}
