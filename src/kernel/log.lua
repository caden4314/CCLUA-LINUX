local M={}
local ring={}
local max=256
local path="/var/log/cclua/kernel.log"
local jsonPath="/var/log/cclua/events.jsonl"
local errorPath="/var/log/cclua/errors.log"

local function now()
  return (os and os.epoch and os.epoch("utc")) or 0
end

local function ensure_log_dir()
  if not fs.exists("var") then fs.makeDir("var") end
  if not fs.exists("var/log") then fs.makeDir("var/log") end
  if not fs.exists("var/log/cclua") then fs.makeDir("var/log/cclua") end
end

local function detail_text(details)
  if details==nil then return "" end
  if type(details)=="table" and textutils and textutils.serializeJSON then
    local ok,v=pcall(textutils.serializeJSON,details)
    if ok and v then return v end
  end
  return tostring(details)
end

local function append(pathname,line)
  local h=fs.open(pathname:gsub("^/",""),"a")
  if not h then return false end
  h.writeLine(line)
  h.close()
  return true
end

local function persist(rec)
  if not fs then return end
  pcall(function()
    ensure_log_dir()
    local details=detail_text(rec.details):gsub("[\r\n]"," ")
    local line=("%d\t%s\t%s\t%s\t%s\t%s"):format(
      rec.timestamp,
      rec.level,
      rec.subsystem,
      rec.pid and tostring(rec.pid) or "-",
      rec.message:gsub("[\r\n]"," "),
      details
    )
    append(path,line)
    if textutils and textutils.serializeJSON then
      local ok,json=pcall(textutils.serializeJSON,rec)
      if ok and json then append(jsonPath,json) end
    end
    if rec.level=="error" or rec.level=="critical" then append(errorPath,line) end
  end)
end

function M.write(level,subsystem,message,details,pid)
  local r={
    timestamp=now(),
    level=level or "info",
    subsystem=subsystem or "kernel",
    pid=pid,
    message=tostring(message or ""),
    details=details
  }
  ring[#ring+1]=r
  if #ring>max then table.remove(ring,1) end
  persist(r)
  return r
end

function M.entries()
  local o={}
  for i,v in ipairs(ring) do o[i]=v end
  return o
end

function M.path() return path end
function M.json_path() return jsonPath end
function M.error_path() return errorPath end
function M.clear() ring={} end
return M
