return {main=function(ctx,args)
 local out=nil;local head=false;local url=nil;local silent=false;local i=1
 while i<=#args do
  local a=args[i]
  if (a=="-o" or a=="--output") and args[i+1] then out=args[i+1];i=i+2
  elseif a=="-I" or a=="--head" then head=true;i=i+1
  elseif a=="-s" or a=="--silent" then silent=true;i=i+1
  elseif a:sub(1,1)=="-" then i=i+1
  else url=a;i=i+1 end
 end
 if not url then print("curl: no URL specified");return 2 end
 if not http then print("curl: HTTP API disabled");return 1 end
 local h,err=http.get(url)
 if not h then if not silent then print("curl: "..tostring(err))end;return 1 end
 if head then
  if h.getResponseCode then local c,msg=h.getResponseCode();print("HTTP "..tostring(c).." "..tostring(msg or ""))end
  if h.getResponseHeaders then for k,v in pairs(h.getResponseHeaders())do print(k..": "..tostring(v))end end
  h.close();return 0
 end
 local data=h.readAll();h.close()
 if out then local f=fs.open(out:gsub("^/",""),"wb") or fs.open(out:gsub("^/",""),"w");if not f then return 1 end;f.write(data);f.close()
 else write(data) end
 return 0
end}
