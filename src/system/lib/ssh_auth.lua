local crypto=ISO.require("system/lib/crypto/init.lua")
local identity=ISO.require("system/lib/identity.lua")
local M={}
local ROOT="/.cclua/data/system/ssh"
local AUTH=ROOT.."/authorized_keys.db"
local KNOWN=ROOT.."/known_hosts.db"

local function ensure()
  if not fs.exists(ROOT) then fs.makeDir(ROOT) end
end

local function readTable(path)
  ensure()
  if not fs.exists(path) then return {} end
  local h=fs.open(path,"r");if not h then return {} end
  local raw=h.readAll();h.close()
  local ok,t=pcall(textutils.unserialize,raw)
  return ok and type(t)=="table" and t or {}
end

local function writeTable(path,t)
  ensure()
  local h=assert(fs.open(path,"w"))
  h.write(textutils.serialize(t,{compact=true}))
  h.close()
end

function M.hostKey()
  return identity.getOrCreate("ssh-host")
end

function M.userKey()
  return identity.getOrCreate("ssh-user")
end

function M.fingerprint(public)
  return crypto.publicFingerprint(public)
end

function M.authorize(public,label)
  local db=readTable(AUTH)
  local fp=M.fingerprint(public)
  db[fp]={public=public,label=label or fp,added=os.epoch and os.epoch("utc") or 0}
  writeTable(AUTH,db)
  return fp
end

function M.revoke(fingerprint)
  local db=readTable(AUTH)
  db[fingerprint]=nil
  writeTable(AUTH,db)
end

function M.isAuthorized(public)
  local fp=M.fingerprint(public)
  local db=readTable(AUTH)
  return db[fp]~=nil,db[fp],fp
end

function M.authorized()
  return readTable(AUTH)
end

function M.checkHost(address,public,trustOnFirstUse)
  local db=readTable(KNOWN)
  local fp=M.fingerprint(public)
  local rec=db[address]
  if not rec then
    if not trustOnFirstUse then return nil,"unknown host",fp end
    db[address]={public=public,fingerprint=fp,firstSeen=os.epoch and os.epoch("utc") or 0}
    writeTable(KNOWN,db)
    return true,"new",fp
  end
  if rec.fingerprint~=fp then return nil,"host key changed",fp end
  return true,"known",fp
end

function M.knownHosts()
  return readTable(KNOWN)
end

return M
