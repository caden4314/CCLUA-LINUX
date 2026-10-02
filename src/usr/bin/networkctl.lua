local config=dofile("/usr/lib/cclua/config.lua")
return {main=function(ctx,args)
 local m=config.machine()
 local cmd=args[1] or "list"
 if cmd=="list" then
  print("IDX LINK   TYPE     OPERATIONAL SETUP")
  print("  1 lo     loopback carrier     unmanaged")
  print("  2 cclua0 ether    routable    configured")
  return 0
 elseif cmd=="status" then
  print("● 2: cclua0")
  print("                     Link File: n/a")
  print("                  Network File: /etc/systemd/network/10-cclua.network")
  print("                          Type: ether")
  print("                         State: routable (configured)")
  print("                       Address: "..(m.address or "-"))
  print("                       Gateway: "..(m.manager or "-"))
  return 0
 end
 print("networkctl: supported: list, status");return 1
end}
