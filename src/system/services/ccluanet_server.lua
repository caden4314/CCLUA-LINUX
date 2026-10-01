local crypto=ISO.require("system/lib/crypto/init.lua")
local identity=ISO.require("system/lib/identity.lua")
local codec=ISO.require("system/lib/net/codec.lua")
local M={}
local CHANNELS={discover=47100,control=47101,data=47102}
local MAGIC="CCNET/1"
local STATE="/.cclua/data/server/ccluanet.db"

local function ensureDir()
  if not fs.exists("/.cclua/data/server") then fs.makeDir("/.cclua/data/server") end
end
local function loadState()
  ensureDir()
  if not fs.exists(STATE) then return {leases={},nextHost=10,diagnostics={}} end
  local h=fs.open(STATE,"r");if not h then return {leases={},nextHost=10,diagnostics={}} end
  local raw=h.readAll();h.close()
  local ok,t=pcall(textutils.unserialize,raw)
  if ok and type(t)=="table" then
    t.leases=t.leases or {};t.nextHost=t.nextHost or 10;t.diagnostics=t.diagnostics or {}
    return t
  end
  return {leases={},nextHost=10,diagnostics={}}
end
local function saveState(t)
  ensureDir()
  local h=assert(fs.open(STATE,"w"))
  h.write(textutils.serialize(t,{compact=true}));h.close()
end

function M.new(ctx)
  local self={
    ctx=ctx,state=loadState(),clients={},byAddress={},pending={},
    modem=nil,modemName=nil,timer=nil,packets=0,dropped=0,
  }
  local serverKey=identity.getOrCreate("ccluanet-server")
  local serverId="srv-"..crypto.publicFingerprint(serverKey.public):gsub("[^%x]",""):sub(1,12)

  local function openModem()
    local found=ctx.peripherals:wirelessModems()
    if #found==0 then return nil,"wireless modem required" end
    self.modem,self.modemName=found[1].handle,found[1].device.name
    for _,ch in pairs(CHANNELS) do
      if not self.modem.isOpen(ch) then self.modem.open(ch) end
    end
    return true
  end

  local function tx(channel,msg)
    if not self.modem and not openModem() then return false end
    self.modem.transmit(channel,CHANNELS.control,msg)
    return true
  end

  local function addressFor(deviceId)
    local old=self.state.leases[deviceId]
    if old then return old end
    local n=self.state.nextHost
    self.state.nextHost=n+1
    local third=math.floor(n/250)
    local fourth=(n%250)+2
    local address=("10.200.%d.%d"):format(third,fourth)
    self.state.leases[deviceId]=address
    saveState(self.state)
    return address
  end

  local function frameAad(frame)
    return codec.canonical({
      magic=frame.magic,type=frame.type,msgId=frame.msgId,
      src=frame.src,dst=frame.dst,srcPort=frame.srcPort,dstPort=frame.dstPort,
    })
  end

  local function secureFor(client,frame,payload)
    local plain=textutils.serialize(payload,{compact=true})
    frame.secure=crypto.seal(client.key,crypto.random(12),plain,frameAad(frame))
    return frame
  end

  local function offer(msg)
    if type(msg.deviceId)~="string" or type(msg.public)~="table" or type(msg.nonce)~="string" then return end
    local serverNonce=crypto.encoding.toBase64(crypto.random(16))
    local challenge=crypto.encoding.toBase64(crypto.random(16))
    self.pending[msg.deviceId]={
      public=msg.public,clientNonce=msg.nonce,serverNonce=serverNonce,
      challenge=challenge,created=os.clock(),
    }
    tx(CHANNELS.control,{
      magic=MAGIC,type="OFFER",dst=msg.deviceId,serverId=serverId,
      public=serverKey.public,challenge=challenge,serverNonce=serverNonce,
    })
  end

  local function join(msg)
    local p=self.pending[msg.deviceId]
    if not p or p.serverNonce~=msg.serverNonce or p.clientNonce~=msg.clientNonce or
       p.challenge~=msg.challenge then return end
    local body={
      type="JOIN",deviceId=msg.deviceId,serverId=msg.serverId,
      clientNonce=msg.clientNonce,serverNonce=msg.serverNonce,
      challenge=msg.challenge,public=msg.public,version=msg.version,
    }
    if not crypto.verify(msg.public,codec.canonical(body),msg.signature) then
      self.dropped=self.dropped+1;return
    end
    local shared=crypto.sharedSecret(serverKey.private,msg.public)
    if not shared then self.dropped=self.dropped+1;return end
    local key=crypto.deriveSession(shared,msg.clientNonce,msg.serverNonce,"ccluanet"):sub(1,32)
    local address=addressFor(msg.deviceId)
    local client={
      deviceId=msg.deviceId,address=address,public=msg.public,key=key,
      lastSeen=os.clock(),version=msg.version,
    }
    self.clients[msg.deviceId]=client
    self.byAddress[address]=client
    self.pending[msg.deviceId]=nil

    local welcome={
      type="WELCOME",dst=msg.deviceId,serverId=serverId,address=address,
      clientNonce=msg.clientNonce,serverNonce=msg.serverNonce,lease=300,
    }
    welcome.signature=crypto.sign(serverKey.private,codec.canonical(welcome))
    welcome.magic=MAGIC
    tx(CHANNELS.control,welcome)
  end

  local function readAll(path)
    if not fs.exists(path) then return nil end
    local h=fs.open(path,"r");if not h then return nil end
    local d=h.readAll();h.close();return d
  end

  local function releaseImage()
    local staged="/.cclua/data/server/releases/current.luaiso"
    if fs.exists(staged) then return readAll(staged) end
    return readAll("/.cclua/boot/CCLUA-LINUX.luaiso")
  end

  local function releaseManifest(raw)
    local chunkSize=2048
    local chunks=math.ceil(#raw/chunkSize)
    local meta={
      schema="cclua.update.v1",
      version=ctx.config.version,
      build=ctx.config.build,
      size=#raw,sha256=crypto.sha256(raw,false),
      chunks=chunks,chunkSize=chunkSize,
      architecture=ctx.config.architecture,
    }
    meta.signature=crypto.sign(serverKey.private,codec.canonical({
      schema=meta.schema,version=meta.version,build=meta.build,size=meta.size,
      sha256=meta.sha256,chunks=meta.chunks,chunkSize=meta.chunkSize,
      architecture=meta.architecture,
    }))
    return meta
  end

  local function handleServer(payload,sender,frame)
    if frame.dstPort==9100 and payload.schema=="cclua.diagnostics.v1" then
      self.state.diagnostics[sender.deviceId]={
        at=os.epoch and os.epoch("utc") or 0,
        address=sender.address,data=payload,
      }
      saveState(self.state)
      return nil
    end

    if frame.dstPort==9200 then
      local raw=releaseImage()
      if not raw then return {op="ERROR",message="no release image"} end
      local manifest=releaseManifest(raw)
      if payload.op=="CHECK" then
        local available=payload.version~=manifest.version or payload.build~=manifest.build
        return {
          op="MANIFEST",available=available,
          manifest=available and {
            schema=manifest.schema,version=manifest.version,build=manifest.build,
            size=manifest.size,sha256=manifest.sha256,chunks=manifest.chunks,
            chunkSize=manifest.chunkSize,architecture=manifest.architecture,
          } or nil,
          signature=available and manifest.signature or nil,
        }
      elseif payload.op=="GET_CHUNK" then
        local index=tonumber(payload.index)
        if not index or index<1 or index>manifest.chunks then
          return {op="ERROR",message="invalid chunk"}
        end
        local first=(index-1)*manifest.chunkSize+1
        local data=raw:sub(first,math.min(#raw,first+manifest.chunkSize-1))
        return {
          op="CHUNK",index=index,
          data=crypto.encoding.toBase64(data),
          sha256=crypto.sha256(data,false),
        }
      end
    end

    if frame.dstPort==9300 then
      local root="/.cclua/data/server/packages"
      if not fs.exists(root) then fs.makeDir(root) end
      if payload.op=="LIST" then
        local list={}
        for _,name in ipairs(fs.list(root)) do
          if name:match("%.luapkg$") then list[#list+1]=name:gsub("%.luapkg$","") end
        end
        table.sort(list)
        return {op="LIST",packages=list}
      elseif payload.op=="GET" and type(payload.name)=="string" then
        local safe=payload.name:gsub("[^%w%._%-]","")
        local raw=readAll(root.."/"..safe..".luapkg")
        if not raw then return {op="ERROR",message="package not found"} end
        return {
          op="PACKAGE",name=safe,
          data=crypto.encoding.toBase64(raw),
          sha256=crypto.sha256(raw,false),
          signature=crypto.sign(serverKey.private,raw),
        }
      end
    end
    return {op="ERROR",message="unknown server service"}
  end

  local function ack(sender,original)
    local frame={
      magic=MAGIC,type="ACK",msgId=original.msgId,
      src="@server",dst=sender.address,srcPort=0,dstPort=original.srcPort,
    }
    secureFor(sender,frame,{ok=true})
    tx(CHANNELS.data,frame)
  end

  local function reply(sender,original,payload)
    if payload==nil then return end
    local frame={
      magic=MAGIC,type="ROUTE",
      msgId="srv-"..tostring(os.clock()).."-"..tostring(math.random(1,999999)),
      src="@server",dst=sender.address,
      srcPort=original.dstPort,dstPort=original.srcPort,
    }
    secureFor(sender,frame,payload)
    tx(CHANNELS.data,frame)
  end

  local function route(frame)
    local sender=self.byAddress[frame.src]
    if not sender or type(frame.secure)~="table" then self.dropped=self.dropped+1;return end
    local plain=crypto.open(sender.key,frame.secure,frameAad(frame))
    if not plain then self.dropped=self.dropped+1;return end
    local ok,payload=pcall(textutils.unserialize,plain)
    if not ok or type(payload)~="table" then self.dropped=self.dropped+1;return end
    sender.lastSeen=os.clock();self.packets=self.packets+1
    ack(sender,frame)

    if frame.dst=="@server" then
      local response=handleServer(payload,sender,frame)
      reply(sender,frame,response)
      return
    end

    local dest=self.byAddress[frame.dst]
    if not dest then
      reply(sender,frame,{op="NET_ERROR",message="destination unreachable",dst=frame.dst})
      return
    end
    local outbound={
      magic=MAGIC,type="ROUTE",msgId=frame.msgId,
      src=sender.address,dst=dest.address,
      srcPort=frame.srcPort,dstPort=frame.dstPort,
    }
    secureFor(dest,outbound,payload)
    tx(CHANNELS.data,outbound)
  end

  function self.start()
    local ok,err=openModem()
    if not ok then error(err,0) end
    self.timer=os.startTimer(5)
  end

  function self.event(event,a,b,c,d,e)
    if event=="modem_message" then
      local side,channel,replyChannel,msg,distance=a,b,c,d,e
      if side~=self.modemName or type(msg)~="table" or msg.magic~=MAGIC then return end
      if channel==CHANNELS.discover and msg.type=="DISCOVER" then
        offer(msg)
      elseif channel==CHANNELS.control then
        if msg.type=="JOIN" then join(msg)
        elseif msg.type=="PING" then
          tx(CHANNELS.control,{magic=MAGIC,type="PONG",src=serverId,dst=msg.src})
        elseif msg.type=="PONG" and msg.src then
          local client=self.byAddress[msg.src];if client then client.lastSeen=os.clock() end
        end
      elseif channel==CHANNELS.data and msg.type=="ROUTE" then
        route(msg)
      end
    elseif event=="peripheral" or event=="peripheral_detach" then
      ctx.peripherals:event(event,a)
      if not self.modem or not peripheral.isPresent(self.modemName) then
        self.modem=nil;self.modemName=nil;openModem()
      end
    elseif event=="timer" and a==self.timer then
      local now=os.clock()
      for id,p in pairs(self.pending) do if now-p.created>15 then self.pending[id]=nil end end
      for id,client in pairs(self.clients) do
        if now-client.lastSeen>60 then
          self.byAddress[client.address]=nil;self.clients[id]=nil
        else
          tx(CHANNELS.control,{magic=MAGIC,type="PING",src=serverId,dst=client.address})
        end
      end
      self.timer=os.startTimer(5)
    end
  end

  function self.status()
    local clients=0;for _ in pairs(self.clients) do clients=clients+1 end
    return {
      serverId=serverId,clients=clients,packets=self.packets,dropped=self.dropped,
      modem=self.modemName,
      fingerprint=crypto.publicFingerprint(serverKey.public),
    }
  end

  function self.stop()
    if self.modem then
      for _,ch in pairs(CHANNELS) do pcall(self.modem.close,ch) end
    end
  end

  return self
end

M.CHANNELS=CHANNELS
M.MAGIC=MAGIC
return M
