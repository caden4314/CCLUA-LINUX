local config=dofile("/usr/lib/cclua/config.lua")
local M={}

M.protocol="cclua-net-v2"
M.port=27027
M.peers={}
M.stats={rx=0,tx=0,last_rx=nil,last_tx=nil}

local function now() return (os.epoch and os.epoch("utc")) or 0 end

function M.machine() return config.machine() end

function M.open_all_modems()
  local opened={}
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name,"modem") then
      local ok=pcall(rednet.open,name)
      if ok then opened[#opened+1]=name end
    end
  end
  return opened
end

function M.packet(kind,payload,dst)
  local me=M.machine()
  return {
    version=2,
    protocol=M.protocol,
    id=("%d-%d-%d"):format(os.getComputerID(),now(),math.random(1000,9999)),
    kind=kind,
    src_id=os.getComputerID(),
    src=me.address,
    hostname=me.hostname,
    role=me.role,
    dst=dst,
    time=now(),
    payload=payload or {}
  }
end

function M.broadcast(kind,payload)
  local p=M.packet(kind,payload,nil)
  rednet.broadcast(p,M.protocol)
  M.stats.tx=M.stats.tx+1
  M.stats.last_tx=now()
  return p
end

function M.send(id,kind,payload)
  local p=M.packet(kind,payload,id)
  rednet.send(id,p,M.protocol)
  M.stats.tx=M.stats.tx+1
  M.stats.last_tx=now()
  return p
end

function M.accept(sender,msg)
  if type(msg)~="table" or msg.protocol~=M.protocol or msg.version~=2 then return nil end
  M.stats.rx=M.stats.rx+1
  M.stats.last_rx=now()
  local peer=M.peers[sender] or {}
  peer.id=sender
  peer.address=msg.src
  peer.hostname=msg.hostname
  peer.role=msg.role
  peer.last_seen=msg.time or now()
  peer.last_message=now()
  if msg.payload and msg.payload.status then peer.status=msg.payload.status end
  M.peers[sender]=peer
  return msg
end

function M.snapshot()
  local out={}
  for _,p in pairs(M.peers) do out[#out+1]=p end
  table.sort(out,function(a,b)return (a.id or 999)<(b.id or 999) end)
  config.write_json("/var/lib/cclua/network.json",{
    schema=1,
    self=M.machine(),
    stats=M.stats,
    peers=out
  })
  return out
end

function M.get_peer(id) return M.peers[tonumber(id)] end
return M
