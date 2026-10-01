local crypto=ISO.require("system/lib/crypto/init.lua")
local codec=ISO.require("system/lib/net/codec.lua")
local auth=ISO.require("system/lib/ssh_auth.lua")
local Shell=ISO.require("system/lib/remote_shell.lua")
local M={}
local PORT=22

function M.new(ctx)
  local self={ctx=ctx,sessions={},accepted=0,rejected=0,lastError=nil}
  local hostKey=auth.hostKey()

  local function net()
    return ctx.services and ctx.services:get("netd")
  end

  local function send(dst,dstPort,payload)
    local n=net();if not n then return nil,"network unavailable" end
    return n:send(dst,dstPort,payload,PORT,true)
  end

  local function helloBody(msg)
    return {
      op="HELLO",session=msg.session,user=msg.user,
      userPublic=msg.userPublic,clientNonce=msg.clientNonce,
    }
  end

  local function secureAad(session,seq,direction)
    return codec.canonical({
      protocol="lua-ssh/1",session=session,seq=seq,direction=direction,
    })
  end

  local function reject(meta,session,reason)
    self.rejected=self.rejected+1
    send(meta.src,meta.srcPort,{protocol="lua-ssh/1",op="REJECT",session=session,reason=reason})
  end

  local function handleHello(msg,meta)
    if type(msg.session)~="string" or type(msg.userPublic)~="table" or
       type(msg.signature)~="table" or type(msg.clientNonce)~="string" then
      return reject(meta,msg.session or "?","invalid hello")
    end

    local authorized,record=auth.isAuthorized(msg.userPublic)
    if not authorized then return reject(meta,msg.session,"public key not authorized") end
    if not crypto.verify(msg.userPublic,codec.canonical(helloBody(msg)),msg.signature) then
      return reject(meta,msg.session,"signature rejected")
    end

    local serverNonce=crypto.encoding.toBase64(crypto.random(16))
    local shared,err=crypto.sharedSecret(hostKey.private,msg.userPublic)
    if not shared then return reject(meta,msg.session,err or "key exchange failed") end
    local material=crypto.deriveSession(shared,msg.clientNonce,serverNonce,"lua-ssh")
    local session={
      id=msg.session,peer=meta.src,peerPort=meta.srcPort,
      user=msg.user or ctx.config.user.name,
      key=material:sub(1,32),serverNonce=serverNonce,
      rx=0,tx=0,shell=Shell.new(ctx,msg.user or ctx.config.user.name),
      clientPublic=msg.userPublic,
    }
    self.sessions[msg.session]=session
    self.accepted=self.accepted+1

    local welcome={
      protocol="lua-ssh/1",op="WELCOME",session=msg.session,
      hostPublic=hostKey.public,serverNonce=serverNonce,
      clientNonce=msg.clientNonce,user=session.user,
    }
    welcome.signature=crypto.sign(hostKey.private,codec.canonical({
      op=welcome.op,session=welcome.session,hostPublic=welcome.hostPublic,
      serverNonce=welcome.serverNonce,clientNonce=welcome.clientNonce,user=welcome.user,
    }))
    send(meta.src,meta.srcPort,welcome)
  end

  local function sendSecure(s,body)
    s.tx=s.tx+1
    local plain=textutils.serialize(body,{compact=true})
    local secure=crypto.seal(s.key,crypto.random(12),plain,secureAad(s.id,s.tx,"server"))
    return send(s.peer,s.peerPort,{
      protocol="lua-ssh/1",op="SECURE",session=s.id,seq=s.tx,secure=secure,
    })
  end

  local function handleSecure(msg)
    local s=self.sessions[msg.session]
    if not s or type(msg.secure)~="table" or type(msg.seq)~="number" then return end
    if msg.seq<=s.rx then return end
    local plain=crypto.open(s.key,msg.secure,secureAad(s.id,msg.seq,"client"))
    if not plain then self.lastError="ssh decrypt failed";return end
    local ok,body=pcall(textutils.unserialize,plain)
    if not ok or type(body)~="table" then return end
    s.rx=msg.seq

    if body.op=="EXEC" then
      local output,code=s.shell:exec(body.line or "")
      sendSecure(s,{op="OUTPUT",text=output,code=code,prompt=s.shell:prompt(),closed=s.shell.closed})
      if s.shell.closed then self.sessions[s.id]=nil end
    elseif body.op=="PING" then
      sendSecure(s,{op="PONG"})
    elseif body.op=="CLOSE" then
      self.sessions[s.id]=nil
    end
  end

  local function onPacket(msg,meta)
    if type(msg)~="table" or msg.protocol~="lua-ssh/1" then return end
    if msg.op=="HELLO" then handleHello(msg,meta)
    elseif msg.op=="SECURE" then handleSecure(msg) end
  end

  function self.start()
    local n=net()
    if n then
      local ok,err=n:bind(PORT,onPacket)
      if not ok then self.lastError=err end
    end
  end

  function self.stop()
    local n=net();if n and n.unbind then n:unbind(PORT) end
    self.sessions={}
  end

  function self.status()
    local count=0;for _ in pairs(self.sessions) do count=count+1 end
    return {
      port=PORT,sessions=count,accepted=self.accepted,rejected=self.rejected,
      hostFingerprint=auth.fingerprint(hostKey.public),lastError=self.lastError,
    }
  end

  return self
end

M.PORT=PORT
return M
