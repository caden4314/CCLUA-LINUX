return {main=function(ctx,args)
 local out=nil;local url=nil;local i=1
 while i<=#args do
  if (args[i]=="-O" or args[i]=="--output-document") and args[i+1] then out=args[i+1];i=i+2
  elseif args[i]:sub(1,1)=="-" then i=i+1
  else url=args[i];i=i+1 end
 end
 if not url then print("wget: missing URL");return 1 end
 if not http then print("wget: HTTP API disabled");return 1 end
 print("--"..(os.date and os.date("%Y-%m-%d %H:%M:%S") or "").."--  "..url)
 local h,err=http.get(url)
 if not h then print("wget: "..tostring(err));return 1 end
 local data=h.readAll();h.close()
 if out then
  local f=fs.open(out:gsub("^/",""),"wb") or fs.open(out:gsub("^/",""),"w")
  if not f then print("wget: cannot write "..out);return 1 end
  f.write(data);f.close();print("saved '"..out.."' ("..#data.." bytes)")
 else write(data) end
 return 0
end}
