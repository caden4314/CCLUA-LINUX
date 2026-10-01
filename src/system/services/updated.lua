local crypto=ISO.require("system/lib/crypto/init.lua")
local codec=ISO.require("system/lib/net/codec.lua")
local M={}
local SERVER_PORT=9200
local LOCAL_PORT=9201
local ACTIVE="/.cclua/boot/CCLUA-LINUX.luaiso"
local STAGE="/.cclua/boot/CCLUA-LINUX.luaiso.new"
local BACKUP="/.cclua/boot/CCLUA-LINUX.luaiso.bak"

local function readAll(path)
  if not fs.exists(path) then return nil end
  local h=fs.open(path,"r");if not h then return nil end
  local d=h.readAll();h.close();return d
end

local function writeAll(path,data,append)
  local h=assert(fs.open(path,append and "a" or "w"))
  h.write(data or "");h.close()
end

function M.new(ctx)
  local self={
    ctx=ctx,timer=nil,interval=60,lastCheck=0,lastError=nil,
    state="idle",manifest=nil,nextChunk=1,received=0,
  }

  local function net()
    return ctx.services and ctx.services:get("netd")
  end

  local function manifestBody(m)
    return {
      schema=m.schema,version=m.version,build=m.build,size=m.size,
      sha256=m.sha256,chunks=m.chunks,chunkSize=m.chunkSize,
      architecture=m.architecture,
    }
  end

  local function requestCheck()
    local n=net();if not n then self.lastError="netd unavailable";return end
    local status=n.status and n.status() or {}
    if status.state~="online" then self.lastError="network offline";return end
    n:send("@server",SERVER_PORT,{
      op="CHECK",replyPort=LOCAL_PORT,
      version=ctx.config.version,build=ctx.config.build,
      architecture=ctx.config.architecture,
    },LOCAL_PORT,true)
    self.lastCheck=os.clock();self.state="checking"
  end

  local function requestChunk(index)
    local n=net();if not n or not self.manifest then return end
    n:send("@server",SERVER_PORT,{
      op="GET_CHUNK",replyPort=LOCAL_PORT,
      version=self.manifest.version,build=self.manifest.build,index=index,
    },LOCAL_PORT,true)
    self.state="downloading"
  end

  local function fail(reason)
    self.state="error";self.lastError=tostring(reason)
    self.manifest=nil;self.nextChunk=1;self.received=0
    if fs.exists(STAGE) then fs.delete(STAGE) end
  end

  local function handleManifest(msg)
    if msg.available~=true then
      self.state="current";self.lastError=nil;return
    end
    if type(msg.manifest)~="table" or type(msg.signature)~="table" then
      return fail("invalid manifest")
    end
    local n=net();local public=n and n.serverPublicKey and n:serverPublicKey()
    if not public then return fail("no server trust key") end
    if not crypto.verify(public,codec.canonical(manifestBody(msg.manifest)),msg.signature) then
      return fail("manifest signature rejected")
    end
    if msg.manifest.architecture and msg.manifest.architecture~=ctx.config.architecture then
      return fail("architecture mismatch")
    end
    self.manifest=msg.manifest
    self.nextChunk=1;self.received=0
    if fs.exists(STAGE) then fs.delete(STAGE) end
    writeAll(STAGE,"",false)
    requestChunk(1)
  end

  local function finish()
    local raw=readAll(STAGE)
    if not raw then return fail("staged image missing") end
    if #raw~=tonumber(self.manifest.size) then return fail("size mismatch") end
    if crypto.sha256(raw,false)~=self.manifest.sha256 then return fail("sha256 mismatch") end
    local first=raw:match("^([^\r\n]+)")
    if first~="CCLUAISO/1" then return fail("invalid luaiso") end

    if fs.exists(BACKUP) then fs.delete(BACKUP) end
    if fs.exists(ACTIVE) then fs.move(ACTIVE,BACKUP) end
    fs.move(STAGE,ACTIVE)
    self.state="installed";self.lastError=nil
    os.queueEvent("cclua_update_installed",self.manifest.version,self.manifest.build)
    self.timer=os.startTimer(2)
  end

  local function onPacket(msg)
    if type(msg)~="table" then return end
    if msg.op=="MANIFEST" then
      handleManifest(msg)
    elseif msg.op=="CHUNK" and self.manifest then
      local index=tonumber(msg.index)
      if index~=self.nextChunk or type(msg.data)~="string" then return fail("chunk order") end
      local data=crypto.encoding.fromBase64(msg.data)
      if not data then return fail("chunk decode") end
      if msg.sha256 and crypto.sha256(data,false)~=msg.sha256 then return fail("chunk hash") end
      writeAll(STAGE,data,true)
      self.received=self.received+#data
      self.nextChunk=self.nextChunk+1
      if self.nextChunk>tonumber(self.manifest.chunks) then finish()
      else requestChunk(self.nextChunk) end
    end
  end

  function self.start()
    local n=net()
    if n then n:bind(LOCAL_PORT,onPacket) end
    self.timer=os.startTimer(4)
  end

  function self.event(event,a)
    if event=="ccluanet_up" then
      requestCheck()
    elseif event=="timer" and a==self.timer then
      if self.state=="installed" then
        os.reboot()
        return
      end
      requestCheck()
      self.timer=os.startTimer(self.interval)
    end
  end

  function self.status()
    return {
      state=self.state,lastCheck=self.lastCheck,lastError=self.lastError,
      received=self.received,
      target=self.manifest and self.manifest.version or nil,
    }
  end

  function self.stop()
    local n=net();if n and n.unbind then n:unbind(LOCAL_PORT) end
    if self.timer then pcall(os.cancelTimer,self.timer) end
  end

  return self
end

M.SERVER_PORT=SERVER_PORT
M.LOCAL_PORT=LOCAL_PORT
return M
