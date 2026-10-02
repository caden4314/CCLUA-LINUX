local config=dofile("/usr/lib/cclua/config.lua")
return {main=function(ctx,args)
 local m=config.machine()
 local cmd=args[1] or "addr"
 if cmd=="addr" or cmd=="a" or cmd=="address" then
  print("1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 state UNKNOWN")
  print("    inet 127.0.0.1/8 scope host lo")
  print("2: cclua0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP")
  print(("    inet %s/24 scope global cclua0"):format(m.address or "0.0.0.0"))
  return 0
 elseif cmd=="route" or cmd=="r" then
  print(("default via %s dev cclua0"):format(m.manager or "10.27.0.1"))
  print(("10.27.0.0/24 dev cclua0 proto kernel scope link src %s"):format(m.address or "0.0.0.0"))
  return 0
 elseif cmd=="link" then
  print("1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 state UNKNOWN")
  print("2: cclua0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP")
  return 0
 end
 print("ip: unsupported object: "..tostring(cmd))
 return 1
end}
