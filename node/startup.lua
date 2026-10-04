-- Generic CCLUA Ubuntu Server node bootloader
local function host(path) return tostring(path):gsub("^/","") end

local function read_json(path,default)
  path=host(path)
  if not fs.exists(path) then return default end
  local h=fs.open(path,"r")
  if not h then return default end
  local raw=h.readAll();h.close()
  local ok,v=pcall(textutils.unserializeJSON,raw)
  if ok and type(v)=="table" then return v end
  return default
end

local function ensure(path)
  path=host(path)
  if path=="" or fs.exists(path) then return end
  local parent=fs.getDir(path)
  if parent~="" and not fs.exists(parent) then ensure(parent) end
  fs.makeDir(path)
end

local function bootlog(msg)
  pcall(function()
    ensure("var/log/cclua")
    local h=fs.open("var/log/cclua/boot.log","a")
    if h then
      h.writeLine(("%d\t%s"):format(os.epoch and os.epoch("utc") or 0,tostring(msg):gsub("[\r\n]"," ")))
      h.close()
    end
  end)
end

local machine=read_json("/etc/cclua/machine.json",{})
if machine.label then os.setComputerLabel(machine.label) end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1,1)
print("CCLUA-LINUX Ubuntu Server")
print(("%s | ID %d"):format(machine.hostname or os.getComputerLabel() or "node",os.getComputerID()))
bootlog("node bootloader start id="..tostring(os.getComputerID()).." role="..tostring(machine.role))

if not fs.exists("System/init/init.lua") then
  bootlog("missing /System/init/init.lua")
  error("No CCLUA Ubuntu Server image installed.",0)
end

local ok,err=pcall(dofile,"/System/init/init.lua")
if not ok then
  bootlog("boot failed: "..tostring(err))
  term.setTextColor(colors.red)
  print("Boot failed: "..tostring(err))
  error(err,0)
end
