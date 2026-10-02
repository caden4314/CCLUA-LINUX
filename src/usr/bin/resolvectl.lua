local config=dofile("/usr/lib/cclua/config.lua")
return {main=function(ctx,args)
 local m=config.machine()
 local cmd=args[1] or "status"
 if cmd=="status" then
  print("Global")
  print("       Protocols: +LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported")
  print("resolv.conf mode: stub")
  print("")
  print("Link 2 (cclua0)")
  print("Current Scopes: DNS")
  print("     Protocols: +DefaultRoute")
  print("   DNS Servers: "..(m.manager or "10.27.0.1"))
  print("    DNS Domain: cclua")
  return 0
 elseif cmd=="query" and args[2] then
  local map={["manager.cclua"]="10.27.0.1",["server-cyan.cclua"]="10.27.0.11",["server-orange.cclua"]="10.27.0.12"}
  local ip=map[args[2]]
  if ip then print(args[2]..": "..ip.." -- link: cclua0");return 0 end
  print(args[2]..": resolve call failed: Name not found");return 1
 end
 print("resolvectl: supported: status, query <name>");return 1
end}
