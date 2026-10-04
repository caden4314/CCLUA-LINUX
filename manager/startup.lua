-- CCLUA-LINUX network-manager bootloader
-- This file is intentionally small. GitHub/fleet management runs inside Ubuntu
-- as cclua-managerd.service after /System/init/init.lua starts.

os.setComputerLabel("LINUX_NETWORK")
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1,1)

local ROOT="/var/lib/cclua/github"
local STATE=ROOT.."/state.json"
local INSTALLED="/var/lib/cclua/installed-commit"
local BOOTSTATE="/var/lib/cclua/boot.json"

local function host(path)
  return tostring(path):gsub("^/","")
end

local function ensureDir(path)
  path=host(path)
  if path=="" or fs.exists(path) then return end
  local parent=fs.getDir(path)
  if parent~="" and not fs.exists(parent) then ensureDir(parent) end
  fs.makeDir(path)
end

local function readAll(path)
  path=host(path)
  if not fs.exists(path) then return nil end
  local h=fs.open(path,"r")
  if not h then return nil end
  local v=h.readAll()
  h.close()
  return v
end

local function writeAll(path,data)
  path=host(path)
  ensureDir(fs.getDir(path))
  local h,err=fs.open(path,"w")
  if not h then return nil,err or "open failed" end
  h.write(data)
  h.close()
  return true
end

local function readJson(path,default)
  local raw=readAll(path)
  if not raw then return default end
  local ok,v=pcall(textutils.unserializeJSON,raw)
  if ok and type(v)=="table" then return v end
  return default
end

local function writeJson(path,value)
  return writeAll(path,textutils.serializeJSON(value))
end

local function readText(path)
  local v=readAll(path)
  return v and v:gsub("%s+$","") or nil
end

local function replaceTree(src,dst)
  src=host(src)
  dst=host(dst)
  if not fs.exists(src) then return true end
  if fs.exists(dst) then fs.delete(dst) end
  local ok,err=pcall(fs.copy,src,dst)
  if not ok then return nil,tostring(err) end
  return true
end

local function copyDefaults(src,dst)
  src=host(src)
  dst=host(dst)
  if not fs.exists(src) then return end
  if not fs.exists(dst) then fs.makeDir(dst) end
  for _,name in ipairs(fs.list(src)) do
    local s=fs.combine(src,name)
    local d=fs.combine(dst,name)
    if fs.isDir(s) then
      copyDefaults(s,d)
    elseif not fs.exists(d) then
      fs.copy(s,d)
    end
  end
end

local function copyFile(src,dst)
  src=host(src)
  dst=host(dst)
  if not fs.exists(src) then return end
  if fs.exists(dst) then fs.delete(dst) end
  ensureDir(fs.getDir(dst))
  fs.copy(src,dst)
end

local function slotCommit(slot)
  return readText(ROOT.."/"..slot.."/.commit")
end

local function activate(slot,commit)
  local source=ROOT.."/"..slot
  if not fs.exists(host(source)) then return nil,"cache slot "..tostring(slot).." is missing" end
  if not fs.exists(host(source.."/kernel/init.lua")) then return nil,"slot has no kernel" end
  if not fs.exists(host(source.."/init/init.lua")) then return nil,"slot has no init" end
  if not fs.exists(host(source.."/usr")) then return nil,"slot has no /usr tree" end

  print(("Activating CCLUA image %s [%s]"):format(tostring(commit):sub(1,8),slot))
  writeJson(BOOTSTATE,{
    schema=1,state="ACTIVATING",slot=slot,commit=commit,
    timestamp=os.epoch and os.epoch("utc") or 0
  })

  local trees={
    {source.."/kernel","/System/kernel"},
    {source.."/init","/System/init"},
    {source.."/usr","/usr"},
    {source.."/lib","/lib"},
  }
  for _,pair in ipairs(trees) do
    local ok,err=replaceTree(pair[1],pair[2])
    if not ok then return nil,err end
  end

  -- /etc is persistent machine state. Seed newly introduced defaults without
  -- destroying hostname, users, local configuration or manager identity.
  copyDefaults(source.."/etc","/etc")
  copyFile(source.."/etc/os-release","/etc/os-release")
  copyFile(source.."/etc/issue","/etc/issue")

  ensureDir("/root")
  ensureDir("/home")
  ensureDir("/var/log")
  ensureDir("/var/lib/cclua")
  ensureDir("/etc/cclua")
  ensureDir("/tmp")

  local ok,err=writeAll(INSTALLED,tostring(commit).."\n")
  if not ok then return nil,err end

  writeJson(BOOTSTATE,{
    schema=1,state="STAGED",slot=slot,commit=commit,
    timestamp=os.epoch and os.epoch("utc") or 0
  })
  return true
end

local function bootSystem(slot,commit)
  writeJson(BOOTSTATE,{
    schema=1,state="BOOTING",slot=slot,commit=commit,
    timestamp=os.epoch and os.epoch("utc") or 0
  })
  local ok,err=pcall(dofile,"/System/init/init.lua")
  if ok then return true end
  return nil,tostring(err)
end

print("CCLUA-LINUX Ubuntu Server bootloader")
print("Computer ID "..tostring(os.getComputerID()))

-- One-time cleanup from the pre-Ubuntu standalone manager runtime.
for _,legacy in ipairs({"github_bridge.lua","github_bridge.lua.old","github_bridge.lua.new"}) do
  if fs.exists(legacy) then pcall(fs.delete,legacy) end
end

local state=readJson(STATE,{})
local slot=state.activeSlot=="B" and "B" or "A"
local commit=state.imageCommit or state.commit or slotCommit(slot)
local installed=readText(INSTALLED)

if commit and (installed~=commit or not fs.exists("System/init/init.lua")) then
  local ok,err=activate(slot,commit)
  if not ok then
    term.setTextColor(colors.red)
    print("Image activation failed: "..tostring(err))
    term.setTextColor(colors.white)
  end
end

if not fs.exists("System/init/init.lua") then
  error("No bootable CCLUA Ubuntu Server image is installed.",0)
end

print("Starting Ubuntu Server...")
local ok,err=bootSystem(slot,commit or installed or "unknown")
if ok then return end

term.setTextColor(colors.red)
print("Primary image failed: "..tostring(err))
term.setTextColor(colors.white)

-- Immediate boot failure: try the other cached slot as last-known-good.
local fallback=slot=="A" and "B" or "A"
local fallbackCommit=slotCommit(fallback)
if fallbackCommit and fs.exists(host(ROOT.."/"..fallback.."/kernel/init.lua")) then
  print(("Rolling back to slot %s (%s)"):format(fallback,fallbackCommit:sub(1,8)))
  local activated,aerr=activate(fallback,fallbackCommit)
  if activated then
    state.activeSlot=fallback
    state.imageCommit=fallbackCommit
    state.commit=fallbackCommit
    state.rollbackFrom=commit
    state.rollbackAt=os.epoch and os.epoch("utc") or 0
    writeJson(STATE,state)
    local booted,berr=bootSystem(fallback,fallbackCommit)
    if booted then return end
    err=berr
  else
    err=aerr
  end
end

writeJson(BOOTSTATE,{
  schema=1,state="FAILED",slot=slot,commit=commit,error=tostring(err),
  timestamp=os.epoch and os.epoch("utc") or 0
})
error("CCLUA boot failed: "..tostring(err),0)
