-- Generic CCLUA Ubuntu node bootloader with A/B update activation.
local ROOT="/var/lib/cclua/node-update"
local STATE=ROOT.."/state.json"
local INSTALLED="/var/lib/cclua/installed-commit"
local INSTALLED_MANIFEST=ROOT.."/installed-manifest.json"
local BOOTSTATE="/var/lib/cclua/boot.json"

local function host(path) return tostring(path):gsub("^/","") end

local function ensure(path)
  path=host(path)
  if path=="" or fs.exists(path) then return end
  local parent=fs.getDir(path)
  if parent~="" and not fs.exists(parent) then ensure(parent) end
  fs.makeDir(path)
end

local function read_all(path)
  path=host(path)
  if not fs.exists(path) then return nil end
  local h=fs.open(path,"r")
  if not h then return nil end
  local v=h.readAll();h.close();return v
end

local function write_all(path,data)
  path=host(path)
  ensure(fs.getDir(path))
  local h,err=fs.open(path,"w")
  if not h then return nil,err or "open failed" end
  h.write(data or "");h.close();return true
end

local function read_json(path,default)
  local raw=read_all(path)
  if not raw then return default end
  local ok,v=pcall(textutils.unserializeJSON,raw)
  return ok and type(v)=="table" and v or default
end

local function write_json(path,value)
  return write_all(path,textutils.serializeJSON(value))
end

local function read_text(path)
  local v=read_all(path)
  return v and v:gsub("%s+$","") or nil
end

local function bootlog(msg)
  pcall(function()
    ensure("/var/log/cclua")
    local h=fs.open("var/log/cclua/boot.log","a")
    if h then
      h.writeLine(("%d\t%s"):format(os.epoch and os.epoch("utc") or 0,tostring(msg):gsub("[\r\n]"," ")))
      h.close()
    end
  end)
end

local function slot_root(slot) return ROOT.."/"..tostring(slot) end

local function slot_commit(slot)
  return read_text(slot_root(slot).."/.commit")
end

local function slot_usable(slot)
  local r=host(slot_root(slot))
  return fs.exists(fs.combine(r,"kernel/init.lua"))
    and fs.exists(fs.combine(r,"init/init.lua"))
    and fs.exists(fs.combine(r,"usr"))
    and fs.exists(fs.combine(r,".manifest.json"))
end

local function replace_tree(src,dst)
  src=host(src);dst=host(dst)
  if not fs.exists(src) then
    if fs.exists(dst) then fs.delete(dst) end
    return true
  end
  if fs.exists(dst) then fs.delete(dst) end
  ensure(fs.getDir(dst))
  local ok,err=pcall(fs.copy,src,dst)
  if not ok then return nil,tostring(err) end
  return true
end

local function copy_defaults(src,dst)
  src=host(src);dst=host(dst)
  if not fs.exists(src) then return true end
  if not fs.exists(dst) then fs.makeDir(dst) end
  for _,name in ipairs(fs.list(src)) do
    local s=fs.combine(src,name)
    local d=fs.combine(dst,name)
    if fs.isDir(s) then
      copy_defaults(s,d)
    elseif not fs.exists(d) then
      fs.copy(s,d)
    end
  end
  return true
end

local function copy_file(src,dst)
  src=host(src);dst=host(dst)
  if not fs.exists(src) then return true end
  if fs.exists(dst) then fs.delete(dst) end
  ensure(fs.getDir(dst))
  fs.copy(src,dst)
  return true
end

local machine=read_json("/etc/cclua/machine.json",{})
if machine.label then os.setComputerLabel(machine.label) end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1,1)
local imageName=tostring(machine.image or "ubuntu-22.04-server")
local desktop=imageName:find("desktop",1,true)~=nil or machine.role=="desktop-client"
print(desktop and "CCLUA-LINUX Ubuntu Desktop" or "CCLUA-LINUX Ubuntu Server")
print(("%s | ID %d"):format(machine.hostname or os.getComputerLabel() or "node",os.getComputerID()))
bootlog("node bootloader start id="..tostring(os.getComputerID()).." role="..tostring(machine.role))

local isoPath="Boot/system.luaiso"
local isoPending="Boot/install-pending"
if fs.exists(isoPath) and (fs.exists(isoPending) or not fs.exists("System/init/init.lua")) then
  print("Loading CCLUA .luaiso image...")
  bootlog("luaiso install start path="..isoPath)
  local okLoader,loader=pcall(dofile,"luaiso.lua")
  if not okLoader or type(loader)~="table" then
    error("CCLUA image loader unavailable: "..tostring(loader),0)
  end
  local result,isoErr=loader.install(isoPath,{clean=true})
  if not result then
    bootlog("luaiso install failed: "..tostring(isoErr))
    error("CCLUA .luaiso install failed: "..tostring(isoErr),0)
  end
  write_json("/var/lib/cclua/luaiso.json",{
    schema=1,role=result.role,build_id=result.build_id,
    file_count=result.file_count,
    installed_at=os.epoch and os.epoch("utc") or 0
  })
  if fs.exists(isoPending) then fs.delete(isoPending) end
  print(("Image installed: %s (%d files)"):format(tostring(result.role),tonumber(result.file_count) or 0))
  bootlog("luaiso install complete build="..tostring(result.build_id))
end

local function activate(slot,commit,recordPrevious)
  if not slot_usable(slot) then return nil,"slot "..tostring(slot).." is not bootable" end
  local source=slot_root(slot)
  local state=read_json(STATE,{schema=1,activeSlot="A"})
  local oldActive=state.activeSlot

  print(("Activating update %s [%s]"):format(tostring(commit):sub(1,8),tostring(slot)))
  bootlog(("activate slot=%s commit=%s"):format(tostring(slot),tostring(commit)))
  write_json(BOOTSTATE,{
    schema=2,state="ACTIVATING",slot=slot,commit=commit,
    timestamp=os.epoch and os.epoch("utc") or 0
  })

  local mappings={
    {source.."/kernel","System/kernel"},
    {source.."/init","System/init"},
    {source.."/usr","usr"},
    {source.."/lib","lib"},
  }
  for _,m in ipairs(mappings) do
    local ok,err=replace_tree(m[1],m[2])
    if not ok then return nil,err end
  end

  copy_defaults(source.."/etc","etc")
  copy_file(source.."/etc/os-release","etc/os-release")
  copy_file(source.."/etc/issue","etc/issue")

  ensure("/root");ensure("/home");ensure("/var/log/cclua");ensure("/var/lib/cclua");ensure("/etc/cclua");ensure("/tmp")

  local ok,err=write_all(INSTALLED,tostring(commit).."\n")
  if not ok then return nil,err end
  local manifest=read_all(source.."/.manifest.json")
  if manifest then write_all(INSTALLED_MANIFEST,manifest) end

  if recordPrevious~=false and oldActive~=slot and slot_usable(oldActive) then
    state.previousSlot=oldActive
  end
  state.activeSlot=slot
  state.pendingSlot=nil
  state.pendingCommit=nil
  state.installedCommit=commit
  state.activatedAt=os.epoch and os.epoch("utc") or 0
  state.lastResult="activated"
  write_json(STATE,state)

  write_json(BOOTSTATE,{
    schema=2,state="STAGED",slot=slot,commit=commit,
    timestamp=os.epoch and os.epoch("utc") or 0
  })
  return true
end

local state=read_json(STATE,{schema=1,activeSlot="A"})
if state.pendingSlot and state.pendingCommit then
  local ok,err=activate(state.pendingSlot,state.pendingCommit,true)
  if not ok then
    state.lastResult="activation-failed"
    state.lastError=tostring(err)
    write_json(STATE,state)
    write_json(BOOTSTATE,{
      schema=2,state="ACTIVATION_FAILED",slot=state.pendingSlot,commit=state.pendingCommit,
      error=tostring(err),timestamp=os.epoch and os.epoch("utc") or 0
    })
    bootlog("activation failed: "..tostring(err))
    error("CCLUA update activation failed: "..tostring(err),0)
  end
end

if not fs.exists("System/init/init.lua") then
  bootlog("missing /System/init/init.lua")
  error("No CCLUA Ubuntu image installed.",0)
end

local activeState=read_json(STATE,{schema=1,activeSlot="A"})
local installed=read_text(INSTALLED) or "unknown"
write_json(BOOTSTATE,{
  schema=2,state="BOOTING",slot=activeState.activeSlot,commit=installed,
  timestamp=os.epoch and os.epoch("utc") or 0
})
bootlog(("boot slot=%s commit=%s"):format(tostring(activeState.activeSlot),tostring(installed)))

local ok,err=pcall(dofile,"/System/init/init.lua")
if ok then return end

bootlog("primary image failed: "..tostring(err))
term.setTextColor(colors.red)
print("Primary image failed: "..tostring(err))
term.setTextColor(colors.white)

local fallback=activeState.previousSlot
local fallbackCommit=fallback and slot_commit(fallback) or nil
if fallback and fallbackCommit and slot_usable(fallback) then
  print(("Rolling back to slot %s (%s)"):format(tostring(fallback),fallbackCommit:sub(1,8)))
  bootlog(("rollback slot=%s commit=%s"):format(tostring(fallback),fallbackCommit))
  local rolled,rollbackErr=activate(fallback,fallbackCommit,false)
  if rolled then
    local s=read_json(STATE,{schema=1})
    s.lastResult="rollback"
    s.rollbackFrom=installed
    s.rollbackAt=os.epoch and os.epoch("utc") or 0
    write_json(STATE,s)
    local booted,bootErr=pcall(dofile,"/System/init/init.lua")
    if booted then return end
    err=bootErr
  else
    err=rollbackErr
  end
end

write_json(BOOTSTATE,{
  schema=2,state="FAILED",slot=activeState.activeSlot,commit=installed,error=tostring(err),
  timestamp=os.epoch and os.epoch("utc") or 0
})
bootlog("boot failed: "..tostring(err))
error("CCLUA boot failed: "..tostring(err),0)
