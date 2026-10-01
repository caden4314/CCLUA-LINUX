local crypto=ISO.require("system/lib/crypto/init.lua")
local M={}
local SERVER_PORT=9300
local LOCAL_PORT=9301

function M.new(ctx)
  local self={ctx=ctx,remote={},lastError=nil,pending=nil,installs=0}

  local function net()
    return ctx.services and ctx.services:get("netd")
  end

  local function request(payload)
    local n=net()
    if not n then return nil,"netd unavailable" end
    local s=n.status and n.status() or {}
    if s.state~="online" then return nil,"network offline" end
    return n:send("@server",SERVER_PORT,payload,LOCAL_PORT,true)
  end

  function self:refresh()
    self.pending="list"
    local id,err=request({op="LIST"})
    if not id then self.pending=nil;self.lastError=err;return nil,err end
    return true
  end

  function self:install(name)
    if type(name)~="string" or name=="" then return nil,"package name required" end
    self.pending="install:"..name
    local id,err=request({op="GET",name=name})
    if not id then self.pending=nil;self.lastError=err;return nil,err end
    return true
  end

  local function onPacket(msg)
    if type(msg)~="table" then return end
    if msg.op=="LIST" and type(msg.packages)=="table" then
      self.remote=msg.packages;self.pending=nil;self.lastError=nil
      os.queueEvent("cclua_pkg_event","list",msg.packages)
    elseif msg.op=="PACKAGE" and type(msg.data)=="string" then
      local raw=crypto.encoding.fromBase64(msg.data)
      if not raw or crypto.sha256(raw,false)~=msg.sha256 then
        self.pending=nil;self.lastError="package hash mismatch"
        os.queueEvent("cclua_pkg_event","error",self.lastError)
        return
      end
      local n=net();local public=n and n.serverPublicKey and n:serverPublicKey()
      if not public then
        self.pending=nil;self.lastError="server key unavailable"
        os.queueEvent("cclua_pkg_event","error",self.lastError)
        return
      end
      local rec,err=ctx.packages:installRaw(raw,"ccluanet",msg.signature,public)
      self.pending=nil
      if not rec then
        self.lastError=err;os.queueEvent("cclua_pkg_event","error",err)
      else
        self.lastError=nil;self.installs=self.installs+1
        os.queueEvent("cclua_pkg_event","installed",rec.name,rec.version)
      end
    elseif msg.op=="ERROR" then
      self.pending=nil;self.lastError=msg.message
      os.queueEvent("cclua_pkg_event","error",msg.message)
    end
  end

  function self.start()
    local n=net()
    if n then n:bind(LOCAL_PORT,onPacket) end
  end

  function self.event(event)
    if event=="ccluanet_up" then self:refresh() end
  end

  function self.stop()
    local n=net();if n and n.unbind then n:unbind(LOCAL_PORT) end
  end

  function self.status()
    return {remote=#self.remote,pending=self.pending,installs=self.installs,lastError=self.lastError}
  end

  return self
end

return M
