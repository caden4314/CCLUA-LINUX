return {main=function(ctx,args)
 if args[1] then
  if ctx.process.uid~=0 then print("hostname: you must be root to change the host name");return 1 end
  local h=fs.open("etc/hostname","w");if not h then print("hostname: cannot write /etc/hostname");return 1 end
  h.writeLine(args[1]);h.close();return 0
 end
 local h=fs.open("etc/hostname","r");print((h and h.readLine()) or "cclua-server");if h then h.close()end
 return 0
end}
