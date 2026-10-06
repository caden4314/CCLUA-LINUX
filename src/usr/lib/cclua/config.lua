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
  local encoded=textutils.serializeJSON(data)

  -- Avoid exposing a half-written JSON document to other services (or host
  -- diagnostics) while the file is being refreshed. Stock/mocked filesystems
  -- without move support retain the direct-write compatibility path.
  if fs.move then
    local tmp=host..".tmp"
    if fs.exists(tmp) then pcall(fs.delete,tmp) end
    local h=fs.open(tmp,"w")
    if not h then return nil,"cannot open "..path.." temp file" end
    h.write(encoded)
    h.close()

    if fs.exists(host) then pcall(fs.delete,host) end
    local ok,err=pcall(fs.move,tmp,host)
    if ok then return true end
    if fs.exists(tmp) then pcall(fs.delete,tmp) end
    return nil,"cannot replace "..path..": "..tostring(err)
  end

  local h=fs.open(host,"w")
  if not h then return nil,"cannot open "..path end
  h.write(encoded)
  h.close()
  return true
end

function M.machine()
  return M.read_json("/etc/cclua/machine.json",{})
end

return M
