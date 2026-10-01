local crypto=ISO.require("system/lib/crypto/init.lua")
local M={}
local ROOT="/.cclua/data/system/keys"

local function ensure()
  if not fs.exists("/.cclua") then fs.makeDir("/.cclua") end
  if not fs.exists("/.cclua/data") then fs.makeDir("/.cclua/data") end
  if not fs.exists("/.cclua/data/system") then fs.makeDir("/.cclua/data/system") end
  if not fs.exists(ROOT) then fs.makeDir(ROOT) end
end

local function load(path)
  if not fs.exists(path) then return nil end
  local h=fs.open(path,"r");if not h then return nil end
  local raw=h.readAll();h.close()
  local ok,data=pcall(textutils.unserialize,raw)
  if ok and type(data)=="table" then return data end
end

local function save(path,data)
  local h=assert(fs.open(path,"w"))
  h.write(textutils.serialize(data,{compact=true}))
  h.close()
end

function M.get(name)
  ensure()
  return load(ROOT.."/"..tostring(name)..".key")
end

function M.getOrCreate(name)
  ensure()
  local path=ROOT.."/"..tostring(name)..".key"
  local key=load(path)
  if key then return key end
  key=crypto.keypair()
  key.created=os.epoch and os.epoch("utc") or math.floor(os.clock()*1000)
  key.fingerprint=crypto.publicFingerprint(key.public)
  save(path,key)
  return key
end
function M.deviceId()
  local key=M.getOrCreate("network")
  local compact=crypto.sha256(tostring(key.public.x)..":"..tostring(key.public.y),false)
  return "cc-"..compact:sub(1,16)
end

function M.public(name)
  local key=M.getOrCreate(name)
  return key.public,key.fingerprint
end

return M
