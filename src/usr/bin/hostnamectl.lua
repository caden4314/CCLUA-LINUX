local config=dofile("/usr/lib/cclua/config.lua")
return {main=function(ctx,args)
 local m=config.machine()
 if args[1]=="set-hostname" then
  if ctx.process.uid~=0 then print("Failed to set hostname: Access denied");return 1 end
  if not args[2] then print("hostnamectl: missing hostname");return 1 end
  local h=fs.open("etc/hostname","w");h.writeLine(args[2]);h.close()
  m.hostname=args[2];config.write_json("/etc/cclua/machine.json",m)
  return 0
 end
 print(" Static hostname: "..(m.hostname or "cclua-server"))
 print("       Icon name: computer")
 print("         Chassis: server")
 print("      Machine ID: cclua-"..tostring(os.getComputerID()))
 print("         Boot ID: "..tostring(os.epoch("utc")))
 print("Operating System: Ubuntu 22.04.5 LTS [CCLUA]")
 print("          Kernel: 5.15.0-cclua")
 print("    Architecture: cclua")
 return 0
end}
