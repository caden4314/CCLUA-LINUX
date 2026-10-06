local M={}

local drivers=dofile("/usr/lib/cclua/drivers.lua")
local native=dofile("/usr/lib/cclua/native.lua")
local system=dofile("/usr/lib/cclua/api/system.lua")
local config=dofile("/usr/lib/cclua/config.lua")

local function capability_set()
  local caps=drivers.capabilities()
  local set={}
  for _,cap in ipairs(caps or {}) do set[cap]=true end
  return set
end

function M.version()
  return {schema=1,sdk="0.3",kernel_api=1}
end

function M.open(ctx,manifest)
  assert(type(ctx)=="table" and ctx.kernel,"CCLUA SDK requires an application context")
  manifest=type(manifest)=="table" and manifest or {}

  local appName=tostring(ctx.app or manifest.name or "app")
  appName=appName:gsub("[^%w%._%-]","_")
  local appPaths={
    config="/etc/cclua/apps/"..appName,
    data="/var/lib/cclua/apps/"..appName,
    cache="/var/cache/cclua/apps/"..appName,
  }

  local function ensure_dir(path)
    if type(fs)~="table" or type(fs.exists)~="function" or type(fs.makeDir)~="function" then return end
    if not fs.exists(path) then pcall(fs.makeDir,path) end
  end

  for _,path in pairs(appPaths) do ensure_dir(path) end

  local function safe_key(name)
    name=tostring(name or "")
    if name=="" or not name:match("^[%w%._%-]+$") then return nil end
    return name
  end

  local sdk={
    manifest=manifest,
    native=native,
    drivers=drivers,
    app={
      name=appName,
      version=tostring(manifest.version or "0"),
      paths=appPaths,
    },
  }

  function sdk.system()
    return system.snapshot(ctx)
  end

  function sdk.machine()
    return config.machine()
  end

  function sdk.capabilities()
    local list,providers=drivers.capabilities()
    return {list=list,providers=providers,native=drivers.native()}
  end

  function sdk.has(capability)
    return capability_set()[tostring(capability or "")] == true
  end

  function sdk.require(capabilities)
    if type(capabilities)=="string" then capabilities={capabilities} end
    capabilities=type(capabilities)=="table" and capabilities or {}
    local have=capability_set()
    local missing={}
    for _,cap in ipairs(capabilities) do
      cap=tostring(cap)
      if not have[cap] then missing[#missing+1]=cap end
    end
    if #missing>0 then
      return nil,"missing capabilities: "..table.concat(missing,", "),missing
    end
    return true
  end

  function sdk.find(capability)
    return drivers.find(capability)
  end

  function sdk.wrap(name)
    return drivers.wrap(name)
  end

  function sdk.open_device(capability,index)
    local found=drivers.find(tostring(capability or ""))
    local item=found[math.max(1,math.floor(tonumber(index) or 1))]
    if not item then return nil,"no provider for capability "..tostring(capability) end
    local wrapped,err=drivers.wrap(item.name)
    if not wrapped then return nil,err end
    return wrapped,item
  end

  function sdk.path(scope,name)
    scope=tostring(scope or "data")
    local base=appPaths[scope]
    if not base then return nil,"unknown app storage scope" end
    if name==nil then return base end
    local key=safe_key(name)
    if not key then return nil,"invalid app storage key" end
    return base.."/"..key
  end

  function sdk.read_json(scope,name,default)
    local path,err=sdk.path(scope,name)
    if not path then return nil,err end
    return config.read_json(path,default)
  end

  function sdk.write_json(scope,name,value)
    local path,err=sdk.path(scope,name)
    if not path then return nil,err end
    return config.write_json(path,value)
  end

  function sdk.notify(title,message,level)
    local payload={
      app=appName,
      title=tostring(title or appName),
      message=tostring(message or ""),
      level=tostring(level or "info"),
      timestamp=native.epoch_ms(),
    }
    if os.queueEvent then
      os.queueEvent("cclua_notification",payload)
      return true
    end
    return nil,"event queue unavailable"
  end

  function sdk.log(level,message,fields)
    ctx.kernel.log.write(
      tostring(level or "info"),
      "app:"..tostring(ctx.app or manifest.name or "unknown"),
      tostring(message or ""),
      type(fields)=="table" and fields or {},
      ctx.process and ctx.process.pid or nil
    )
    return true
  end

  function sdk.emit(name,...)
    name=tostring(name or "")
    if name=="" then return nil,"event name required" end
    if os.queueEvent then os.queueEvent(name,...) return true end
    return nil,"event queue unavailable"
  end

  function sdk.wait(filter)
    return coroutine.yield("wait_event",filter)
  end

  function sdk.sleep(seconds)
    if ctx.kernel.scheduler and ctx.kernel.scheduler.sleep then
      return ctx.kernel.scheduler.sleep(tonumber(seconds) or 0)
    end
    local ms=(os.epoch and os.epoch("utc") or 0)+math.floor((tonumber(seconds) or 0)*1000)
    return coroutine.yield("sleep",ms)
  end

  function sdk.now()
    return {
      epoch_ms=native.epoch_ms(),
      monotonic_us=native.monotonic_micros(),
    }
  end

  return sdk
end

return M
