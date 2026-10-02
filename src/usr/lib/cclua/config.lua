local M={}

function M.read_json(path,default)
  local host=tostring(path):gsub("^/","")
  if not fs.exists(host) then return default end
  local h=fs.open(host,"r")
  if not h then return default end
  local raw=h.readAll()
  h.close()
  if not textutils or not textutils.unserializeJSON then return default end
  local ok,data=pcall(textutils.unserializeJSON,raw)
  if ok and type(data)=="table" then return data end
  return default
end

function M.write_json(path,data)
  local host=tostring(path):gsub("^/","")
  local dir=fs.getDir(host)
  if dir~="" and not fs.exists(dir) then fs.makeDir(dir) end
  local h=fs.open(host,"w")
  if not h then return nil,"cannot open "..path end
  h.write(textutils.serializeJSON(data))
  h.close()
  return true
end

function M.machine()
  return M.read_json("/etc/cclua/machine.json",{})
end

return M
