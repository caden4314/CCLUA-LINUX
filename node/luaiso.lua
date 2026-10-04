local M={}

local function host(path)
  return tostring(path):gsub("^/","")
end

local function ensure(path)
  path=host(path)
  if path=="" or fs.exists(path) then return true end
  local parent=fs.getDir(path)
  if parent~="" then ensure(parent) end
  fs.makeDir(path)
  return true
end

local function map_path(path)
  if path:sub(1,14)=="system/kernel/" then return "System/kernel/"..path:sub(15) end
  if path:sub(1,12)=="system/init/" then return "System/init/"..path:sub(13) end
  if path:sub(1,11)=="system/usr/" then return "usr/"..path:sub(12) end
  if path:sub(1,11)=="system/lib/" then return "lib/"..path:sub(12) end
  if path:sub(1,11)=="system/etc/" then return "etc/"..path:sub(12) end
end

function M.read(path)
  path=host(path)
  local h=fs.open(path,"r")
  if not h then return nil,"cannot open image" end
  local raw=h.readAll();h.close()
  local ok,img=pcall(textutils.unserializeJSON,raw)
  if not ok or type(img)~="table" then return nil,"invalid image json" end
  local m=img.manifest
  if type(m)~="table" or m.format~="cclua-luaiso" or tonumber(m.format_version)~=1 then
    return nil,"unsupported image format"
  end
  if type(img.files)~="table" then return nil,"image has no files" end
  return img
end

function M.install(path,opts)
  opts=opts or {}
  local img,err=M.read(path)
  if not img then return nil,err end

  if opts.clean then
    for _,tree in ipairs({"System/kernel","System/init","usr","lib"}) do
      if fs.exists(tree) then fs.delete(tree) end
    end
  end

  local count=0
  for _,rec in ipairs(img.files) do
    local dst=map_path(tostring(rec.path or ""))
    if dst then
      local ok,data=pcall(textutils.decodeBase64,tostring(rec.data or ""))
      if not ok or type(data)~="string" then
        return nil,"decode failed: "..tostring(rec.path)
      end
      if tonumber(rec.size) and #data~=tonumber(rec.size) then
        return nil,"size mismatch: "..tostring(rec.path)
      end
      ensure(fs.getDir(dst))
      local h,e=fs.open(dst,"w")
      if not h then return nil,e or ("cannot write "..dst) end
      h.write(data);h.close()
      count=count+1
    end
  end

  return {
    role=img.manifest.role,
    build_id=img.manifest.build_id,
    file_count=count,
    manifest=img.manifest,
  }
end

return M
