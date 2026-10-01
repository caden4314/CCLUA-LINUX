-- CCLUA-LINUX stage-0 bootloader
-- Loads an encoded .luaiso into memory without extracting the system image.
local BOOT_VERSION = "0.1.0"
local DEFAULT_ISO = "/.cclua/boot/CCLUA-LINUX.luaiso"

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64decode(data)
  data = data:gsub("%s+", "")
  local out, buffer, bits = {}, 0, 0
  for i = 1, #data do
    local ch = data:sub(i, i)
    if ch ~= "=" then
      local v = B64:find(ch, 1, true)
      if not v then error("invalid base64 character", 0) end
      buffer = buffer * 64 + (v - 1)
      bits = bits + 6
      while bits >= 8 do
        bits = bits - 8
        local byte = math.floor(buffer / (2 ^ bits)) % 256
        out[#out + 1] = string.char(byte)
      end
      buffer = buffer % (2 ^ bits)
    end
  end
  return table.concat(out)
end
local function crc32(data)
  local crc = 0xFFFFFFFF
  for i = 1, #data do
    crc = bit32.bxor(crc, data:byte(i))
    for _ = 1, 8 do
      local mask = -(bit32.band(crc, 1))
      crc = bit32.bxor(bit32.rshift(crc, 1), bit32.band(0xEDB88320, mask))
    end
  end
  return string.format("%08x", bit32.band(bit32.bnot(crc), 0xFFFFFFFF))
end

local function readAll(path)
  local h = fs.open(path, "r")
  if not h then return nil end
  local data = h.readAll()
  h.close()
  return data
end

local function findIso()
  local candidates = { DEFAULT_ISO, "/CCLUA-LINUX.luaiso", "/disk/CCLUA-LINUX.luaiso" }
  if shell and shell.getRunningProgram then
    local dir = fs.getDir(shell.getRunningProgram())
    candidates[#candidates + 1] = fs.combine(dir, "CCLUA-LINUX.luaiso")
  end
  for _, path in ipairs(candidates) do
    if fs.exists(path) and not fs.isDir(path) then return path end
  end
  return nil
end
local function parseIso(raw)
  local first, rest = raw:match("^([^\n]+)\n(.*)$")
  first = first and first:gsub("\r$", "") or nil
  if first ~= "CCLUAISO/1" then error("unsupported or corrupt .luaiso", 0) end
  local files, meta = {}, {}
  for line in rest:gmatch("[^\r\n]+") do
    local k, v = line:match("^META%s+([^=]+)=(.*)$")
    if k then
      meta[k] = v
    else
      local path64, checksum, data64 = line:match("^FILE%s+(%S+)%s+(%x+)%s+(.*)$")
      if path64 then
        local path, data = b64decode(path64), b64decode(data64)
        if crc32(data) ~= checksum:lower() then
          error("ISO checksum failure: " .. path, 0)
        end
        files[path] = data
      end
    end
  end
  if not files["system/kernel/init.lua"] then error("ISO has no kernel", 0) end
  return meta, files
end

local isoPath = findIso()
if not isoPath then error("CCLUA-LINUX ISO not found", 0) end
local raw = assert(readAll(isoPath), "cannot read ISO")
local meta, files = parseIso(raw)
local ISO = { meta = meta, files = files, path = isoPath, cache = {} }
function ISO.exists(path) return files[path] ~= nil end
function ISO.read(path) return files[path] end
function ISO.list(prefix)
  prefix = (prefix or ""):gsub("^/+", ""):gsub("/+$", "")
  local out, seen = {}, {}
  for path in pairs(files) do
    if prefix == "" or path:sub(1, #prefix) == prefix then
      local rest = prefix == "" and path or path:sub(#prefix + 2)
      local name = rest:match("^([^/]+)")
      if name and not seen[name] then seen[name] = true; out[#out + 1] = name end
    end
  end
  table.sort(out)
  return out
end
function ISO.require(path)
  path = path:gsub("^/+", "")
  if ISO.cache[path] ~= nil then return ISO.cache[path] end
  local src = assert(files[path], "ISO module missing: " .. path)
  local env = setmetatable({ ISO = ISO }, { __index = _G })
  local fn, err = load(src, "@" .. path, "t", env)
  if not fn then error(err, 0) end
  local result = fn()
  if result == nil then result = true end
  ISO.cache[path] = result
  return result
end

local kernel = ISO.require("system/kernel/init.lua")
return kernel.boot(ISO, {
  bootloader = BOOT_VERSION,
  isoPath = isoPath,
  computerId = os.getComputerID(),
  label = os.getComputerLabel(),
  smoke = fs.exists("/.cclua/smoke"),
})
