local crypto=ISO.require("system/lib/crypto/init.lua")
local codec=ISO.require("system/lib/net/codec.lua")
local auth=ISO.require("system/lib/ssh_auth.lua")
local M={}
local PORT=22022
local SSH_PORT=22

function M.new(ctx)
  local self={ctx=ctx,sessions={},lastError=nil}
  local userKey=auth.userKey()

  local function net() return ctx.services and ctx.services:get("netd") end
  local function aad(id,seq,direction)
    return codec.canonical({protocol="lua-ssh/1",session=id,seq=seq,direction=direction})
  end
  local function helloBody(s)
    return {
      op="HELLO",session=s.id,user=s.user,
      userPublic=userKey.public,clientNonce=s.clientNonce,
    }
  end

  local function sendSecure(s,body)
    s.tx=s.tx+1
    local secure=crypto.seal(
      s.key,crypto.random(12),
      textutils.serialize(body,{compact=true}),
      aad(s.id,s.tx,"client")
    )
    return net():send(s.dst,SSH_PORT,{
      protocol="lua-ssh/1",op="SECURE",session=s.id,seq=s.tx,secure=secure,
    },PORT,true)
  end

  function self:connect(dst,user)
    local n=net()
    if not n or (n.status and n.status().state~="online") then return nil,"network offline" end
    local id=crypto.encoding.toBase64(crypto.random(9)):gsub("[^%w]",""):sub(1,12)
    local s={
      id=id,dst=dst,user=user or ctx.config.user.name,
      clientNonce=crypto.encoding.toBase64(crypto.random(16)),
      state="connecting",rx=0,tx=0,
    }
    self.sessions[id]=s
    local hello={
      protocol="lua-ssh/1",op="HELLO",session=id,user=s.user,
      userPublic=userKey.public,clientNonce=s.clientNonce,
    }
    hello.signature=crypto.sign(userKey.private,codec.canonical(helloBody(s)))
    local sent,err=n:send(dst,SSH_PORT,hello,PORT,true)
    if not sent then self.sessions[id]=nil;return nil,err end
    os.queueEvent("cclua_ssh_output",id,"\27[90mConnecting to "..dst.."...\27[0m\n","connecting")
    return id
  end

  function self:exec(id,line)
    local s=self.sessions[id]
    if not s then return nil,"session not found" end
    if s.state~="online" then return nil,"session not ready" end
    return sendSecure(s,{op="EXEC",line=line or ""})
  end

  function self:close(id)
    local s=self.sessions[id]
    if not s then return true end
    if s.state=="online" then pcall(sendSecure,s,{op="CLOSE"}) end
    self.sessions[id]=nil
    os.queueEvent("cclua_ssh_output",id,"Connection closed.\n","closed")
    return true
  end

  local function handleWelcome(msg,meta)
    local s=self.sessions[msg.session]
    if not s or s.dst~=meta.src then return end
    local body={
      op="WELCOME",session=msg.session,hostPublic=msg.hostPublic,
      serverNonce=msg.serverNonce,clientNonce=msg.clientNonce,user=msg.user,
    }
    if type(msg.hostPublic)~="table" or type(msg.signature)~="table" or
       not crypto.verify(msg.hostPublic,codec.canonical(body),msg.signature) then
      self.sessions[msg.session]=nil
      os.queueEvent("cclua_ssh_output",msg.session,"\27[91mHost signature rejected.\27[0m\n","closed")
      return
    end
    local trusted,state,fp=auth.checkHost(s.dst,msg.hostPublic,true)
    if not trusted then
      self.sessions[msg.session]=nil
      os.queueEvent("cclua_ssh_output",msg.session,"\27[91m"..tostring(state)..": "..tostring(fp).."\27[0m\n","closed")
      return
    end
    local shared,err=crypto.sharedSecret(userKey.private,msg.hostPublic)
    if not shared then
      self.sessions[msg.session]=nil;self.lastError=err;return
    end
    local material=crypto.deriveSession(shared,s.clientNonce,msg.serverNonce,"lua-ssh")
    s.key=material:sub(1,32);s.state="online";s.hostFingerprint=fp
    os.queueEvent("cclua_ssh_output",s.id,
      "\27[90mHost key "..fp.." ("..state..")\27[0m\n"..
      "\27[92mSecure lua-ssh session established.\27[0m\n","online")
  end

  local function handleSecure(msg)
    local s=self.sessions[msg.session]
    if not s or s.state~="online" or type(msg.seq)~="number" or msg.seq<=s.rx then return end
    local plain=crypto.open(s.key,msg.secure,aad(s.id,msg.seq,"server"))
    if not plain then self.lastError="ssh decrypt failed";return end
    local ok,body=pcall(textutils.unserialize,plain)
    if not ok or type(body)~="table" then return end
    s.rx=msg.seq
    if body.op=="OUTPUT" then
      os.queueEvent("cclua_ssh_output",s.id,body.text or "",body.closed and "closed" or "online",body.prompt)
      if body.closed then self.sessions[s.id]=nil end
    end
  end

  local function onPacket(msg,meta)
    if type(msg)~="table" or msg.protocol~="lua-ssh/1" then return end
    if msg.op=="WELCOME" then handleWelcome(msg,meta)
    elseif msg.op=="REJECT" then
      self.sessions[msg.session]=nil
      os.queueEvent("cclua_ssh_output",msg.session,"\27[91mSSH rejected: "..tostring(msg.reason).."\27[0m\n","closed")
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
      sessions=count,userFingerprint=auth.fingerprint(userKey.public),
      lastError=self.lastError,
    }
  end

  return self
end

M.PORT=PORT
return M
