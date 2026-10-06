local M={}

local function api()
  return type(ccperf)=="table" and ccperf or nil
end

function M.available()
  return api()~=nil
end

function M.version()
  local p=api()
  if not p or type(p.version)~="function" then return nil end
  local ok,value=pcall(p.version)
  return ok and value or nil
end

function M.capabilities()
  local p=api()
  if not p or type(p.capabilities)~="function" then
    return {api=0,native_clock=false,native_timer=false}
  end
  local ok,value=pcall(p.capabilities)
  return ok and type(value)=="table" and value
    or {api=0,native_clock=false,native_timer=false}
end

function M.computer()
  local p=api()
  if not p or type(p.computer)~="function" then
    return {id=os.getComputerID and os.getComputerID() or -1}
  end
  local ok,value=pcall(p.computer)
  return ok and type(value)=="table" and value or {}
end

function M.monotonic_micros()
  local p=api()
  if p and type(p.monotonicMicros)=="function" then
    local ok,value=pcall(p.monotonicMicros)
    if ok and type(value)=="number" then return value end
  end
  if os.epoch then return os.epoch("utc")*1000 end
  return math.floor(os.clock()*1000000)
end

function M.epoch_ms()
  local p=api()
  if p and type(p.epochMillis)=="function" then
    local ok,value=pcall(p.epochMillis)
    if ok and type(value)=="number" then return value end
  end
  return os.epoch and os.epoch("utc") or math.floor(os.clock()*1000)
end

function M.crc32(data)
  local p=api()
  if not p or type(p.crc32)~="function" then return nil,"native crc32 unavailable" end
  local ok,value=pcall(p.crc32,tostring(data or ""))
  return ok and value or nil,ok and nil or tostring(value)
end

function M.sha256(data)
  local p=api()
  if not p or type(p.sha256)~="function" then return nil,"native sha256 unavailable" end
  local ok,value=pcall(p.sha256,tostring(data or ""))
  return ok and value or nil,ok and nil or tostring(value)
end

function M.deflate(data,level)
  local p=api()
  if not p or type(p.deflate)~="function" then return nil,"native deflate unavailable" end
  local ok,value=pcall(p.deflate,tostring(data or ""),math.floor(tonumber(level) or 6))
  return ok and value or nil,ok and nil or tostring(value)
end

function M.inflate(data,max_bytes)
  local p=api()
  if not p or type(p.inflate)~="function" then return nil,"native inflate unavailable" end
  local ok,value=pcall(p.inflate,data,math.floor(tonumber(max_bytes) or 8388608))
  return ok and value or nil,ok and nil or tostring(value)
end

return M
