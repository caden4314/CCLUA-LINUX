local crypto=ISO.require("system/lib/crypto/init.lua")
local identity=ISO.require("system/lib/identity.lua")
local codec=ISO.require("system/lib/net/codec.lua")
local M={}

local CHANNELS={discover=47100,control=47101,data=47102}
local MAGIC="CCNET/1"
local PIN="/.cclua/data/system/ccluanet-server.pub"

local function readTable(path)
  if not fs.exists(path) then return nil end
  local h=fs.open(path,"r");if not h then return nil end
  local raw=h.readAll();h.close()
  local ok,t=pcall(textutils.unserialize,raw)
  return ok and type(t)=="table" and t or nil
end
local function writeTable(path,t)
  local d=fs.getDir(path);if d~="" and not fs.exists(d) then fs.makeDir(d) end
  local h=assert(fs.open(path,"w"));h.write(textutils.serialize(t,{compact=true}));h.close()
end

function M.new(ctx)
  local self={
    ctx=ctx,state="offline",modem=nil,modemName=nil,
    deviceId=identity.deviceId(),address=nil,serverId=nil,
    serverPublic=readTable(PIN),sessionKey=nil,clientNonce=nil,serverNonce=nil,
    timer=nil,lastRx=0,lastTx=0,retries=0,ports={},pending={},seq=0,
    stats={tx=0,rx=0,dropped=0,reconnects=0,acks=0},
  }
  local netKey=identity.getOrCreate("network")
  local function openModem()
    local found=ctx.peripherals:wirelessModems()
    if #found==0 then
      self.modem=nil;self.modemName=nil;self.state="no-modem"
      return false
    end
    local pick=found[1]
    self.modem,self.modemName=pick.handle,pick.device.name
    for _,ch in pairs(CHANNELS) do
      if not self.modem.isOpen(ch) then self.modem.open(ch) end
    end
    return true
  end

  local function transmit(channel,message)
    if not self.modem and not openModem() then return false end
    self.modem.transmit(channel,CHANNELS.control,message)
    self.lastTx=os.clock();self.stats.tx=self.stats.tx+1
    return true
  end

  local function resetLink(reason)
    self.sessionKey=nil;self.address=nil;self.serverId=nil
    self.clientNonce=nil;self.serverNonce=nil
    self.state=reason or "offline"
    self.stats.reconnects=self.stats.reconnects+1
  end

  local function discover()
    if not openModem() then return end
    self.clientNonce=crypto.encoding.toBase64(crypto.random(16))
    self.state="discovering"
    transmit(CHANNELS.discover,{
      magic=MAGIC,type="DISCOVER",deviceId=self.deviceId,
      version=ctx.config.version,arch=ctx.config.architecture,
      public=netKey.public,nonce=self.clientNonce,
    })
  end

  local function pinServer(public)
    if not self.serverPublic then
      self.serverPublic=public;writeTable(PIN,public);return true
    end
    return tostring(self.serverPublic.x)==tostring(public.x) and
      tostring(self.serverPublic.y)==tostring(public.y)
  end
  local function handleOffer(msg)
    if msg.dst and msg.dst~=self.deviceId then return end
    if not msg.serverId or not msg.public or not msg.challenge or not msg.serverNonce then return end
    if not pinServer(msg.public) then
      self.state="trust-error";return
    end
    self.serverId=msg.serverId;self.serverNonce=msg.serverNonce
    local signed={
      type="JOIN",deviceId=self.deviceId,serverId=self.serverId,
      clientNonce=self.clientNonce,serverNonce=self.serverNonce,
      challenge=msg.challenge,public=netKey.public,
      version=ctx.config.version,
    }
    signed.signature=crypto.sign(netKey.private,codec.canonical(signed))
    self.state="authenticating"
    transmit(CHANNELS.control,signed)
  end

  local function handleWelcome(msg)
    if msg.dst~=self.deviceId or msg.serverId~=self.serverId then return end
    if not self.serverPublic or not msg.signature or not msg.address then return end
    local signed={
      type="WELCOME",dst=msg.dst,serverId=msg.serverId,address=msg.address,
      clientNonce=self.clientNonce,serverNonce=msg.serverNonce,
      lease=msg.lease or 300,
    }
    if not crypto.verify(self.serverPublic,codec.canonical(signed),msg.signature) then
      self.state="auth-failed";return
    end
    local shared,err=crypto.sharedSecret(netKey.private,self.serverPublic)
    if not shared then self.state="crypto-error";return end
    local material=crypto.deriveSession(shared,self.clientNonce,msg.serverNonce,"ccluanet")
    self.sessionKey=material:sub(1,32)
    self.address=msg.address;self.serverNonce=msg.serverNonce
    self.state="online";self.lastRx=os.clock();self.lease=msg.lease or 300
    os.queueEvent("ccluanet_up",self.address,self.serverId)
  end

  local function aadFor(frame)
    return codec.canonical({
      magic=frame.magic,type=frame.type,msgId=frame.msgId,
      src=frame.src,dst=frame.dst,srcPort=frame.srcPort,dstPort=frame.dstPort,
    })
  end
  local function handleSecure(frame)
    if self.state~="online" or not self.sessionKey then return end
    if frame.dst~=self.address and frame.dst~=self.deviceId then return end
    if not frame.secure then return end
    local plain=crypto.open(self.sessionKey,frame.secure,aadFor(frame))
    if not plain then self.stats.dropped=self.stats.dropped+1;return end
    local ok,payload=pcall(textutils.unserialize,plain)
    if not ok then self.stats.dropped=self.stats.dropped+1;return end
    self.lastRx=os.clock();self.stats.rx=self.stats.rx+1

    if frame.type=="ACK" then
      if self.pending[frame.msgId] then
        self.pending[frame.msgId]=nil;self.stats.acks=self.stats.acks+1
      end
      return
    end

    if frame.type=="ROUTE" then
      local handler=self.ports[tonumber(frame.dstPort)]
      if handler then
        pcall(handler,payload,{
          src=frame.src,srcPort=frame.srcPort,dstPort=frame.dstPort,msgId=frame.msgId
        })
      end
      os.queueEvent("ccluanet_packet",frame.src,frame.srcPort,frame.dstPort,payload)
    end
  end

  function self:bind(port,handler)
    port=assert(tonumber(port),"port")
    if self.ports[port] then return nil,"port in use" end
    self.ports[port]=assert(handler,"handler");return true
  end
  function self:serverPublicKey()
    return self.serverPublic
  end
  function self:serverIdentity()
    return self.serverId
  end
  function self:unbind(port) self.ports[tonumber(port)]=nil end

  function self:send(dst,dstPort,payload,srcPort,reliable)
    if self.state~="online" or not self.sessionKey then return nil,"network offline" end
    self.seq=self.seq+1
    local frame={
      magic=MAGIC,type="ROUTE",msgId=self.deviceId.."-"..self.seq,
      src=self.address,dst=dst,srcPort=srcPort or 49152,dstPort=dstPort,
    }
    local plain=textutils.serialize(payload,{compact=true})
    frame.secure=crypto.seal(self.sessionKey,crypto.random(12),plain,aadFor(frame))
    if not transmit(CHANNELS.data,frame) then return nil,"transmit failed" end
    if reliable~=false then
      self.pending[frame.msgId]={frame=frame,at=os.clock(),tries=1}
    end
    return frame.msgId
  end
  local function retryPending()
    local now=os.clock()
    for id,p in pairs(self.pending) do
      if now-p.at>=1.0 then
        if p.tries>=5 then
          self.pending[id]=nil
          self.stats.dropped=self.stats.dropped+1
        else
          transmit(CHANNELS.data,p.frame)
          p.at=now;p.tries=p.tries+1
        end
      end
    end
  end

  function self.start()
    discover()
    self.timer=os.startTimer(1)
  end

  function self.event(event,a,b,c,d,e)
    if event=="modem_message" then
      local side,channel,reply,message,distance=a,b,c,d,e
      if side~=self.modemName or type(message)~="table" then return end
      if message.magic~=MAGIC then return end
      crypto.random(1)
      if channel==CHANNELS.control then
        if message.type=="OFFER" then handleOffer(message)
        elseif message.type=="WELCOME" then handleWelcome(message)
        elseif message.type=="PING" and self.state=="online" then
          self.lastRx=os.clock()
          transmit(CHANNELS.control,{magic=MAGIC,type="PONG",src=self.address,dst=self.serverId})
        elseif message.type=="PONG" and self.state=="online" then
          self.lastRx=os.clock()
        elseif message.type=="REKEY" then
          resetLink("rekey");discover()
        end
      elseif channel==CHANNELS.data then
        handleSecure(message)
      end
    elseif event=="peripheral" or event=="peripheral_detach" then
      ctx.peripherals:event(event,a)
      if not self.modem or not peripheral.isPresent(self.modemName) then
        resetLink("no-modem");openModem()
      end
    elseif event=="timer" and a==self.timer then
      local now=os.clock()
      retryPending()
      if self.state~="online" then
        discover()
      elseif now-self.lastRx>15 then
        transmit(CHANNELS.control,{magic=MAGIC,type="PING",src=self.address,dst=self.serverId})
      end
      if self.state=="online" and now-self.lastRx>35 then resetLink("timeout") end
      self.timer=os.startTimer(1)
    end
  end
  function self.status()
    local peers=0
    return {
      state=self.state,address=self.address,server=self.serverId,
      modem=self.modemName,deviceId=self.deviceId,
      pending=(function()local n=0;for _ in pairs(self.pending) do n=n+1 end;return n end)(),
      ports=(function()local n=0;for _ in pairs(self.ports) do n=n+1 end;return n end)(),
      stats=self.stats,peers=peers,
    }
  end

  function self.stop()
    -- Kernel may restart this protected daemon immediately.
    if self.modem then
      for _,ch in pairs(CHANNELS) do pcall(self.modem.close,ch) end
    end
    resetLink("stopped")
  end

  return self
end

M.CHANNELS=CHANNELS
M.MAGIC=MAGIC
return M
