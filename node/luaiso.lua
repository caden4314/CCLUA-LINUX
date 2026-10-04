local M={}

-- Do not depend on textutils.decodeBase64. It is not available in every
-- CC:Tweaked build/configuration we support, and the boot image loader must
-- work before the rest of userspace is installed.
local B64="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64MAP={}
for i=1,#B64 do B64MAP[B64:sub(i,i)]=i-1 end

local nativeBase64=nil
pcall(function() nativeBase64=require("cc.base64") end)

local function decode_base64(input)
  input=tostring(input or ""):gsub("%s","")
  if nativeBase64 and type(nativeBase64.decode)=="function" then
    local data,err=nativeBase64.decode(input)
    if type(data)=="string" then return data end
    -- Fall through to the boot-safe decoder. This keeps old/new CC:Tweaked
    -- runtimes compatible even if the optional module rejects the input.
  end
  if #input%4~=0 then return nil,"invalid base64 length" end

  local out={}
  for i=1,#input,4 do
    local c1=input:sub(i,i)
    local c2=input:sub(i+1,i+1)
    local c3=input:sub(i+2,i+2)
    local c4=input:sub(i+3,i+3)

    local a=B64MAP[c1]
    local b=B64MAP[c2]
    local c=(c3=="=") and 0 or B64MAP[c3]
    local d=(c4=="=") and 0 or B64MAP[c4]
    if a==nil or b==nil or c==nil or d==nil then
      return nil,"invalid base64 character"
    end

    local n=a*262144+b*4096+c*64+d
    out[#out+1]=string.char(math.floor(n/65536)%256)
    if c3~="=" then out[#out+1]=string.char(math.floor(n/256)%256) end
    if c4~="=" then out[#out+1]=string.char(n%256) end
  end
  return table.concat(out)
end

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
      local data,decodeErr=decode_base64(rec.data)
      if type(data)~="string" then
        return nil,"decode failed: "..tostring(rec.path)..": "..tostring(decodeErr)
      end
      if tonumber(rec.size) and #data~=tonumber(rec.size) then
        return nil,"size mismatch: "..tostring(rec.path)
      end
      ensure(fs.getDir(dst))
      local h,e=fs.open(dst,"wb")
      if not h then return nil,e or ("cannot write "..dst) end
      h.write(data);h.close()
      count=count+1
      if count%16==0 and type(sleep)=="function" then sleep(0) end
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
