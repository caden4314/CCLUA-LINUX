local M = {}
local LinuxFS=ISO.require("system/kernel/linuxfs.lua")

local function clean(path)
  path = tostring(path or "/"):gsub("\\", "/")
  if path == "" then path = "/" end
  if path:sub(1, 1) ~= "/" then path = "/" .. path end
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then
      if #parts > 0 then table.remove(parts) end
    elseif part ~= "." and part ~= "" then
      parts[#parts + 1] = part
    end
  end
  return "/" .. table.concat(parts, "/")
end

local function ensure(path)
  if not fs.exists(path) then fs.makeDir(path) end
end

function M.new(iso, config)
  local self = {}
  local linux=LinuxFS.new(config)
  local base = "/.cclua/data"
  local userRoot = base .. "/users/" .. config.user.name
  local homeAlias = "/home/" .. config.user.name
  local legacyHome = "/Users/" .. config.user.name
  local appRoot = base .. "/apps"
  local tempRoot = base .. "/tmp"
  ensure(base); ensure(base .. "/users"); ensure(userRoot); ensure(appRoot); ensure(tempRoot)

  local function map(path)
    path = clean(path)
    if path == "/System" or path:sub(1, 8) == "/System/" then
      local rel = path == "/System" and "system" or ("system/" .. path:sub(9))
      return "iso", rel, true
    elseif path == legacyHome or path:sub(1,#(legacyHome.."/"))==legacyHome.."/" then
      local rel = path == legacyHome and "" or path:sub(#legacyHome+2)
      return "host",fs.combine(userRoot,rel),false
    elseif path == "/AppData" or path:sub(1, 9) == "/AppData/" then
      local rel = path == "/AppData" and "" or path:sub(10)
      return "host", fs.combine(appRoot, rel), false
    elseif path == "/Temp" or path:sub(1, 6) == "/Temp/" then
      local rel = path == "/Temp" and "" or path:sub(7)
      return "host", fs.combine(tempRoot, rel), false
    elseif path == homeAlias or path:sub(1, #(homeAlias .. "/")) == homeAlias .. "/" then
      local rel = path == homeAlias and "" or path:sub(#homeAlias + 2)
      return "host", fs.combine(userRoot, rel), false
    elseif linux:exists(path) then
      return "linux", path, true
    end
    return "virtual", path, true
  end

  function self.normalize(path) return clean(path) end
  function self.resolve(path) return map(path) end
  function self.exists(path)
    local kind, target = map(path)
    if kind == "iso" then
      if iso.exists(target) then return true end
      local prefix = target:gsub("/+$", "") .. "/"
      for p in pairs(iso.files) do if p:sub(1, #prefix) == prefix then return true end end
      return false
    elseif kind == "host" then return fs.exists(target)
    elseif kind == "linux" then return linux:exists(clean(path))
    else return path == "/" or path == "/Users" or path == "/System" or path == "/AppData" or path == "/Temp" or path == "/home" end
  end
  function self.isDir(path)
    local kind, target = map(path)
    if kind == "host" then return fs.exists(target) and fs.isDir(target) end
    if kind == "linux" then return linux:isDir(clean(path)) end
    if kind == "iso" then
      local prefix = target:gsub("/+$", "") .. "/"
      for p in pairs(iso.files) do if p:sub(1, #prefix) == prefix then return true end end
      return false
    end
    return self.exists(path)
  end

  function self.list(path)
    path = clean(path)
    local kind, target = map(path)
    if kind == "host" then
      if not fs.exists(target) or not fs.isDir(target) then return nil, "not a directory" end
      return fs.list(target)
    elseif kind == "iso" then
      local prefix = target:gsub("/+$", "")
      return iso.list(prefix)
    elseif kind == "linux" then
      return linux:list(path)
    elseif path == "/" then
      return {"AppData", "System", "Temp", "Users", "bin", "boot", "dev", "etc", "home", "mnt", "opt", "proc", "run", "srv", "usr", "var"}
    elseif path == "/Users" then
      return {config.user.name}
    elseif path == "/home" then
      return {config.user.name}
    end
    return nil, "not a directory"
  end

  function self.read(path)
    local kind, target = map(path)
    if kind == "iso" then return iso.read(target) end
    if kind == "linux" then return linux:read(clean(path)) end
    if kind ~= "host" or not fs.exists(target) or fs.isDir(target) then return nil, "not a file" end
    local h = fs.open(target, "r")
    if not h then return nil, "open failed" end
    local data = h.readAll(); h.close(); return data
  end
  function self.write(path, data, append)
    local kind, target, readOnly = map(path)
    if readOnly or kind ~= "host" then return nil, "read-only filesystem" end
    local dir = fs.getDir(target)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local h = fs.open(target, append and "a" or "w")
    if not h then return nil, "open failed" end
    h.write(data or ""); h.close(); return true
  end

  function self.mkdir(path)
    local kind, target, readOnly = map(path)
    if readOnly or kind ~= "host" then return nil, "read-only filesystem" end
    if not fs.exists(target) then fs.makeDir(target) end
    return true
  end

  function self.delete(path)
    local kind, target, readOnly = map(path)
    if readOnly or kind ~= "host" then return nil, "read-only filesystem" end
    if not fs.exists(target) then return nil, "not found" end
    fs.delete(target); return true
  end

  function self.stat(path)
    local kind, target, readOnly = map(path)
    if not self.exists(path) then return nil, "not found" end
    local dir = self.isDir(path)
    return {
      path = clean(path), kind = kind, readOnly = readOnly,
      directory = dir,
      size = (kind == "host" and not dir) and fs.getSize(target) or 0,
    }
  end

  function self:setCommandProvider(fn)
    linux:setCommandProvider(fn)
  end

  self.userRoot, self.appRoot, self.tempRoot = userRoot, appRoot, tempRoot
  self.linux=linux
  return self
end

return M
