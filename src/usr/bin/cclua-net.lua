local config=dofile("/usr/lib/cclua/config.lua")
return {main=function(ctx,args)
 local data=config.read_json("/var/lib/cclua/network.json",{peers={},stats={}})
 local self=data.self or config.machine()
 print(("Self: %s (%s) role=%s"):format(self.hostname or "-",self.address or "-",self.role or "-"))
 print(("RX=%s TX=%s peers=%d"):format((data.stats or {}).rx or 0,(data.stats or {}).tx or 0,#(data.peers or {})))
 for _,p in ipairs(data.peers or {}) do
  local age=math.max(0,(os.epoch("utc")-(p.last_message or 0))/1000)
  print(("ID %-2s %-14s %-12s role=%-7s age=%.1fs"):format(tostring(p.id),p.hostname or "-",p.address or "-",p.role or "-",age))
 end
 return 0
end}
