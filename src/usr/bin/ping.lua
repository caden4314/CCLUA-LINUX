local config=dofile("/usr/lib/cclua/config.lua")
local net=dofile("/usr/lib/cclua/net.lua")

local function resolve(target)
  local aliases={
    ["server-cyan"]=0,["SERVER_CYAN"]=0,["10.27.0.11"]=0,
    ["server-orange"]=1,["SERVER_ORANGE"]=1,["10.27.0.12"]=1,
    ["manager"]=2,["SERVER_RED"]=2,["10.27.0.1"]=2
  }
  local n=tonumber(target)
  if n then return n end
  if aliases[target]~=nil then return aliases[target] end

  local data=config.read_json("/var/lib/cclua/network.json",{peers={}})
  for _,p in ipairs(data.peers or {}) do
    if p.hostname==target or p.address==target then return p.id end
  end
  return nil
end

return {main=function(ctx,args)
  local target=args[1]
  if not target then print("ping: usage: ping <host|ip|id>");return 2 end
  local id=resolve(target)
  if id==nil then print("ping: "..target..": Name or service not known");return 2 end
  if id==os.getComputerID() then
    print("PING "..target.." (local): 0 ms")
    return 0
  end

  net.open_all_modems()
  print(("PING %s (computer %d) CCLUA NET v2"):format(target,id))

  local okcount=0
  for seq=1,4 do
    local nonce=("%d-%d"):format(os.epoch("utc"),seq)
    local start=os.epoch("utc")
    net.send(id,"ping",{nonce=nonce,seq=seq})
    local timer=os.startTimer(1)
    local got=false
    while not got do
      local ev,a,b,c=coroutine.yield("wait_event",{"rednet_message","timer"})
      if ev=="rednet_message" and a==id and c==net.protocol and type(b)=="table" and b.kind=="pong" and b.payload and b.payload.nonce==nonce then
        if os.cancelTimer then pcall(os.cancelTimer,timer) end
        local ms=os.epoch("utc")-start
        print(("reply from computer %d: seq=%d time=%dms"):format(id,seq,ms))
        okcount=okcount+1;got=true
      elseif ev=="timer" and a==timer then
        print(("timeout: seq=%d"):format(seq))
        got=true
      end
    end
  end
  print(("%d packets transmitted, %d received"):format(4,okcount))
  return okcount>0 and 0 or 1
end}
