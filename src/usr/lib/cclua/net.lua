local config=dofile("/usr/lib/cclua/config.lua")
local M={}

M.protocol="cclua-net-v2"
M.port=27027
M.peers={}
M.stats={
  rx=0,tx=0,tx_failed=0,
  duplicates=0,invalid=0,
  last_rx=nil,last_tx=nil,last_error=nil
}

local sequence=0
local seen={}
local seenCount=0

function M.stats_snapshot()
  return {
    rx=M.stats.rx or 0,
    tx=M.stats.tx or 0,
    tx_failed=M.stats.tx_failed or 0,
    duplicates=M.stats.duplicates or 0,
    invalid=M.stats.invalid or 0,
    last_rx=M.stats.last_rx,
    last_tx=M.stats.last_tx,
    last_error=M.stats.last_error,
  }
end

local function now()
  return (os.epoch and os.epoch("utc")) or 0
end

local function prune_seen()
  local cutoff=now()-120000
  for id,stamp in pairs(seen) do
    if tonumber(stamp or 0)<cutoff then
      seen[id]=nil
      seenCount=math.max(0,seenCount-1)
    end
  end
end

function M.machine()
  return config.machine()
end

function M.open_management_modems()
  local wireless={}
  local fallback={}

  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name,"modem") then
      local modem=peripheral.wrap(name)
      local ok,isWireless=pcall(function()
        return modem and modem.isWireless and modem.isWireless()
      end)
      if ok and isWireless then wireless[#wireless+1]=name
      else fallback[#fallback+1]=name end
    end
  end

  local opened={}
  local function try_open(list)
    for _,name in ipairs(list) do
      local ok,err=pcall(rednet.open,name)
      local isOpen=false
      if ok then
        if rednet.isOpen then
          local statusOk,status=pcall(rednet.isOpen,name)
          isOpen=statusOk and status==true
        else
          isOpen=true
        end
      end
      if isOpen then
        opened[#opened+1]=name
      else
        M.stats.last_error="failed to open modem "..tostring(name)..": "..tostring(err or "not open")
      end
    end
  end

  if #wireless>0 then try_open(wireless) end
  -- Prefer wireless/ender modems, but do not strand a node if those are
  -- present yet unusable. Fall back to wired modems when none opened.
  if #opened==0 and #fallback>0 then try_open(fallback) end
  return opened
end

function M.open_all_modems()
  return M.open_management_modems()
end

function M.packet(kind,payload,dst)
  local me=M.machine()
  sequence=(sequence+1)%1000000
  local stamp=now()
  return {
    version=2,
    protocol=M.protocol,
    id=("%d-%d-%06d"):format(os.getComputerID(),stamp,sequence),
    sequence=sequence,
    kind=kind,
    src_id=os.getComputerID(),
    src=me.address,
    hostname=me.hostname,
    role=me.role,
    dst=dst,
    time=stamp,
    payload=payload or {}
  }
end

function M.broadcast(kind,payload)
  local p=M.packet(kind,payload,nil)
  local ok=rednet.broadcast(p,M.protocol)
  if ok==false then
    M.stats.tx_failed=M.stats.tx_failed+1
    M.stats.last_error="broadcast failed"
  else
    M.stats.tx=M.stats.tx+1
    M.stats.last_tx=now()
  end
  return p,ok~=false
end

function M.send(id,kind,payload)
  local target=tonumber(id)
  local p=M.packet(kind,payload,target)
  local ok=rednet.send(target,p,M.protocol)
  if not ok then
    M.stats.tx_failed=M.stats.tx_failed+1
    M.stats.last_error="send failed to ID "..tostring(target)
  else
    M.stats.tx=M.stats.tx+1
    M.stats.last_tx=now()
  end
  return p,ok==true
end

function M.accept(sender,msg)
  if type(msg)~="table" or msg.protocol~=M.protocol or msg.version~=2 then
    M.stats.invalid=M.stats.invalid+1
    return nil
  end
  if msg.dst~=nil and tonumber(msg.dst)~=os.getComputerID() then
    M.stats.invalid=M.stats.invalid+1
    return nil
  end

  local id=tostring(msg.id or "")
  if id=="" then
    M.stats.invalid=M.stats.invalid+1
    return nil
  end
  if seen[id] then
    M.stats.duplicates=M.stats.duplicates+1
    return nil
  end
  seen[id]=now()
  seenCount=seenCount+1
  if seenCount>512 then prune_seen() end

  M.stats.rx=M.stats.rx+1
  M.stats.last_rx=now()
  local peer=M.peers[tonumber(sender)] or {}
  peer.id=tonumber(sender)
  peer.address=msg.src
  peer.hostname=msg.hostname
  peer.role=msg.role
  peer.remote_time=msg.time
  peer.last_seen=now()
  peer.last_message=now()
  peer.last_packet_id=id
  peer.last_sequence=msg.sequence
  if msg.payload and msg.payload.status then peer.status=msg.payload.status end
  M.peers[tonumber(sender)]=peer
  return msg
end

function M.snapshot(extra)
  local out={}
  for _,p in pairs(M.peers) do out[#out+1]=p end
  table.sort(out,function(a,b)return (a.id or 999)<(b.id or 999) end)
  local payload={
    schema=2,
    self=M.machine(),
    stats=M.stats_snapshot(),
    peers=out,
    timestamp=now(),
  }
  if type(extra)=="table" then
    for k,v in pairs(extra) do payload[k]=v end
  end
  config.write_json("/var/lib/cclua/network.json",payload)
  return out
end

function M.get_peer(id)
  return M.peers[tonumber(id)]
end

return M
