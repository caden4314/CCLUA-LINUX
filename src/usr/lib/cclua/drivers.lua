local M={}
local native=dofile("/usr/lib/cclua/native.lua")

local DRIVER_VERSION=1

local descriptors={
  monitor={
    driver="cc.monitor",class="display",
    capabilities={"display.terminal","display.touch"},
  },
  speaker={
    driver="cc.speaker",class="audio",
    capabilities={"audio.output","audio.pcm48","audio.sound","audio.note"},
  },
  modem={
    driver="cc.modem",class="network",
    capabilities={"network.modem","network.packet"},
  },
  printer={
    driver="cc.printer",class="printer",
    capabilities={"print.text","print.pages"},
  },
  drive={
    driver="cc.drive",class="storage",
    capabilities={"storage.removable","media.disk"},
  },
  redstone_relay={
    driver="cc.redstone-relay",class="gpio",
    capabilities={"gpio.redstone.input","gpio.redstone.output"},
  },
  computer={
    driver="cc.computer",class="compute",
    capabilities={"compute.remote"},
  },
  command={
    driver="cc.command",class="control",
    capabilities={"minecraft.command"},
  },
}

local pluginsLoaded=false
local pluginFiles={}
local DRIVER_DIR="/usr/lib/cclua/drivers.d"

local function copy_list(list)
  local out={}
  for i,v in ipairs(list or {}) do out[i]=v end
  return out
end

local function load_plugins()
  if pluginsLoaded then return end
  pluginsLoaded=true
  if type(fs)~="table" or type(fs.exists)~="function"
    or type(fs.list)~="function" or not fs.exists(DRIVER_DIR) then return end

  for _,file in ipairs(fs.list(DRIVER_DIR)) do
    if file:match("%.lua$") then
      local path=DRIVER_DIR.."/"..file
      local ok,mod=pcall(dofile,path)
      if ok and type(mod)=="table" then
        local entries=type(mod.types)=="table" and mod.types or mod
        local loaded=0
        for kind,desc in pairs(entries) do
          if type(kind)=="string" and type(desc)=="table"
            and type(desc.driver)=="string" then
            descriptors[kind]={
              driver=desc.driver,
              class=tostring(desc.class or "peripheral"),
              capabilities=copy_list(desc.capabilities),
              source=file,
            }
            loaded=loaded+1
          end
        end
        pluginFiles[#pluginFiles+1]={file=file,loaded=loaded,error=nil}
      else
        pluginFiles[#pluginFiles+1]={file=file,loaded=0,error=tostring(mod)}
      end
    end
  end
end

local function sorted_keys(map)
  local out={}
  for k in pairs(map or {}) do out[#out+1]=k end
  table.sort(out)
  return out
end

local function peripheral_names()
  if type(peripheral)~="table" or type(peripheral.getNames)~="function" then return {} end
  local ok,list=pcall(peripheral.getNames)
  return ok and type(list)=="table" and list or {}
end

local function types_for(name)
  load_plugins()
  local out={}
  if type(peripheral)~="table" then return out end
  if peripheral.getType then
    local ok,a,b,c=pcall(peripheral.getType,name)
    if ok then
      for _,v in ipairs({a,b,c}) do
        if type(v)=="string" and v~="" then out[#out+1]=v end
      end
    end
  end
  if #out==0 and type(peripheral.hasType)=="function" then
    for kind in pairs(descriptors) do
      local ok,v=pcall(peripheral.hasType,name,kind)
      if ok and v then out[#out+1]=kind end
    end
  end
  table.sort(out)
  return out
end

local function methods_for(name)
  if type(peripheral)~="table" or type(peripheral.getMethods)~="function" then return {} end
  local ok,methods=pcall(peripheral.getMethods,name)
  if not ok or type(methods)~="table" then return {} end
  table.sort(methods)
  return methods
end

local function capabilities_for(types,methods)
  load_plugins()
  local caps={}
  local seen={}
  local driver=nil
  local class=nil
  for _,kind in ipairs(types or {}) do
    local d=descriptors[kind]
    if d then
      driver=driver or d.driver
      class=class or d.class
      for _,cap in ipairs(d.capabilities or {}) do
        if not seen[cap] then seen[cap]=true;caps[#caps+1]=cap end
      end
    end
  end
  local methodSet={}
  for _,m in ipairs(methods or {}) do methodSet[m]=true end
  if methodSet.framebufferInfo and methodSet.framebufferPresent then
    for _,cap in ipairs({"display.rgb888","display.framebuffer","display.direct"}) do
      if not seen[cap] then seen[cap]=true;caps[#caps+1]=cap end
    end
  end
  if methodSet.playAudio then
    if not seen["audio.stream"] then seen["audio.stream"]=true;caps[#caps+1]="audio.stream" end
  end
  table.sort(caps)
  return driver or "cc.peripheral",class or "peripheral",caps
end

function M.describe(name)
  if type(name)~="string" or name=="" then return nil,"invalid peripheral name" end
  local present=false
  for _,n in ipairs(peripheral_names()) do
    if n==name then present=true;break end
  end
  if not present then return nil,"peripheral not present" end

  local types=types_for(name)
  local methods=methods_for(name)
  local driver,class,caps=capabilities_for(types,methods)
  return {
    schema=1,name=name,driver=driver,driver_version=DRIVER_VERSION,
    class=class,types=types,methods=methods,capabilities=caps,
  }
end

function M.scan()
  load_plugins()
  local out={}
  for _,name in ipairs(peripheral_names()) do
    local d=M.describe(name)
    if d then out[#out+1]=d end
  end
  table.sort(out,function(a,b)return a.name<b.name end)
  return out
end

function M.registry()
  load_plugins()
  local out={}
  for kind,desc in pairs(descriptors) do
    out[#out+1]={
      type=kind,driver=desc.driver,class=desc.class or "peripheral",
      capabilities=copy_list(desc.capabilities),
      source=desc.source or "builtin",
    }
  end
  table.sort(out,function(a,b)return a.type<b.type end)
  return out
end

function M.plugins()
  load_plugins()
  local out={}
  for i,item in ipairs(pluginFiles) do
    out[i]={file=item.file,loaded=item.loaded,error=item.error}
  end
  return out
end

function M.native()
  local caps=native.capabilities()
  local list={}
  for k,v in pairs(caps or {}) do
    if v==true then list[#list+1]="native."..tostring(k) end
  end
  table.sort(list)
  return {
    schema=1,name="ccperf",driver="ccperf.native",
    driver_version=tonumber(caps.api) or 0,class="platform",
    capabilities=list,version=native.version(),available=native.available(),
  }
end

function M.capabilities()
  local set={}
  local providers={}
  for _,device in ipairs(M.scan()) do
    for _,cap in ipairs(device.capabilities or {}) do
      set[cap]=true
      providers[cap]=providers[cap] or {}
      providers[cap][#providers[cap]+1]=device.name
    end
  end
  local n=M.native()
  if n.available then
    for _,cap in ipairs(n.capabilities or {}) do
      set[cap]=true
      providers[cap]=providers[cap] or {}
      providers[cap][#providers[cap]+1]="ccperf"
    end
  end
  return sorted_keys(set),providers
end

function M.find(capability)
  capability=tostring(capability or "")
  local out={}
  for _,device in ipairs(M.scan()) do
    for _,cap in ipairs(device.capabilities or {}) do
      if cap==capability then out[#out+1]=device;break end
    end
  end
  return out
end

function M.wrap(name)
  local desc,err=M.describe(name)
  if not desc then return nil,err end
  return peripheral.wrap(name),desc
end

function M.has(name,capability)
  local d=M.describe(name)
  if not d then return false end
  for _,cap in ipairs(d.capabilities or {}) do
    if cap==capability then return true end
  end
  return false
end

return M
