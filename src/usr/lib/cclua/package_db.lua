local M={}
local config=dofile("/usr/lib/cclua/config.lua")

local function role()
  local m=config.machine()
  local image=tostring(m.image or "")
  if m.role=="desktop-client" or image:find("desktop",1,true) then return "desktop" end
  return "server"
end

function M.role()
  return role()
end

function M.path()
  if role()=="desktop" then
    return "/usr/share/cclua/ubuntu-desktop-packages.json"
  end
  return "/usr/share/cclua/ubuntu-server-packages.json"
end

function M.load()
  local path=M.path():gsub("^/","")
  local h=fs.open(path,"r")
  if not h then return {schema=1,role=role(),packages={}} end
  local raw=h.readAll()
  h.close()
  local ok,data=pcall(textutils.unserializeJSON,raw)
  if not ok or type(data)~="table" then
    return {schema=1,role=role(),packages={}}
  end
  return data
end

function M.find(name)
  for _,p in ipairs(M.load().packages or {}) do
    if p.name==name then return p end
  end
end

return M
