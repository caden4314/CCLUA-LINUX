local M={devices={}}

local CATEGORY={
  printer="output",
  speaker="audio",
  monitor="display",
  modem="network",
  drive="storage",
  redstone_relay="io",
  computer="compute",
  turtle="compute",
  inventory="storage",
  fluid_storage="storage",
  energy_storage="power",
}

local function has_type(types,kind)
  for _,t in ipairs(types or {}) do if t==kind then return true end end
  return false
end

local function safe(obj,method,...)
  if not obj or type(obj[method])~="function" then return nil end
  local ok,a,b,c=pcall(obj[method],...)
  if not ok then return nil end
  return a,b,c
end

local function status_for(name,types)
  local obj=peripheral.wrap(name)
  if not obj then return {} end
  local s={}

  if has_type(types,"printer") then
    s.ink=safe(obj,"getInkLevel")
    s.paper=safe(obj,"getPaperLevel")
  end

  if has_type(types,"speaker") then
    s.audio_ready=true
    s.sample_rate=48000
  end

  if has_type(types,"monitor") then
    local w,h=safe(obj,"getSize")
    s.width=w;s.height=h
    s.text_scale=safe(obj,"getTextScale")
  end

  if has_type(types,"modem") then
    s.wireless=safe(obj,"isWireless")==true
  end

  if has_type(types,"drive") then
    s.present=safe(obj,"isDiskPresent")==true
    s.label=safe(obj,"getDiskLabel")
    s.audio_title=safe(obj,"getAudioTitle")
    s.disk_id=safe(obj,"getDiskID")
  end

  return s
end

local function describe(name)
  local types={peripheral.getType(name)}
  local methods={}
  if peripheral.getMethods then
    local ok,res=pcall(peripheral.getMethods,name)
    if ok and type(res)=="table" then
      methods=res
      table.sort(methods)
    end
  end

  local primary=types[1] or "peripheral"
  for _,preferred in ipairs({"printer","speaker","monitor","modem","drive","redstone_relay"}) do
    if has_type(types,preferred) then primary=preferred break end
  end

  return {
    name=name,
    type=primary,
    primary_type=primary,
    category=CATEGORY[primary] or "peripheral",
    types=types,
    methods=methods,
    status=status_for(name,types),
    present=true
  }
end

function M.scan(kernel)
  local previous=M.devices
  local current={}
  if peripheral then
    for _,name in ipairs(peripheral.getNames()) do
      current[name]=describe(name)
    end
  end

  if kernel and kernel.log then
    for name,dev in pairs(current) do
      if not previous[name] then
        kernel.log.write("info","device","peripheral attached: "..name,{
          types=dev.types,category=dev.category
        })
      end
    end
    for name,dev in pairs(previous) do
      if not current[name] then
        kernel.log.write("warning","device","peripheral detached: "..name,{types=dev.types})
      end
    end
  end

  M.devices=current
  return current
end

function M.get(name) return M.devices[name] end

function M.list(kind)
  local out={}
  for _,dev in pairs(M.devices) do
    if not kind or dev.type==kind or has_type(dev.types,kind) or dev.category==kind then
      out[#out+1]=dev
    end
  end
  table.sort(out,function(a,b)return a.name<b.name end)
  return out
end

function M.wrap(name)
  local dev=M.devices[name]
  if not dev then return nil,"device not found: "..tostring(name) end
  local obj=peripheral.wrap(name)
  if not obj then return nil,"device unavailable: "..tostring(name) end
  return obj,dev
end

function M.call(name,method,...)
  local obj,err=M.wrap(name)
  if not obj then return nil,err end
  if type(obj[method])~="function" then
    return nil,"method not supported: "..tostring(method)
  end
  local ok,a,b,c,d=pcall(obj[method],...)
  if not ok then return nil,tostring(a) end
  return true,a,b,c,d
end

function M.snapshot(path)
  path=path or "/var/lib/cclua/peripherals.json"
  local payload={
    schema=2,
    computer_id=os.getComputerID and os.getComputerID() or nil,
    devices={}
  }
  for _,dev in pairs(M.devices) do payload.devices[#payload.devices+1]=dev end
  table.sort(payload.devices,function(a,b)return a.name<b.name end)

  if fs and textutils and textutils.serializeJSON then
    pcall(function()
      if not fs.exists("var") then fs.makeDir("var") end
      if not fs.exists("var/lib") then fs.makeDir("var/lib") end
      if not fs.exists("var/lib/cclua") then fs.makeDir("var/lib/cclua") end
      local h=fs.open(path:gsub("^/",""),"w")
      if h then h.write(textutils.serializeJSON(payload));h.close() end
    end)
  end
  return payload
end

return M
