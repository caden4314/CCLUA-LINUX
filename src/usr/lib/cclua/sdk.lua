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
  return {schema=1,sdk="0.2",kernel_api=1}
end

function M.open(ctx,manifest)
  assert(type(ctx)=="table" and ctx.kernel,"CCLUA SDK requires an application context")
  manifest=type(manifest)=="table" and manifest or {}

  local sdk={
    manifest=manifest,
    native=native,
    drivers=drivers,
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
