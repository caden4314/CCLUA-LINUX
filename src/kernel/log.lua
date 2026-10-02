local M={}
local ring={}
local max=256
local path="/var/log/cclua/kernel.log"

local function now()
  return (os and os.epoch and os.epoch("utc")) or 0
end

local function persist(rec)
  if not fs then return end
  pcall(function()
    if not fs.exists("var") then fs.makeDir("var") end
    if not fs.exists("var/log") then fs.makeDir("var/log") end
    if not fs.exists("var/log/cclua") then fs.makeDir("var/log/cclua") end
    local h=fs.open(path:gsub("^/",""),"a")
    if not h then return end
    h.writeLine(("%d\t%s\t%s\t%s\t%s"):format(
      rec.timestamp,
      rec.level,
      rec.subsystem,
      rec.pid and tostring(rec.pid) or "-",
      rec.message:gsub("[\r\n]"," ")
    ))
    h.close()
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
function M.clear() ring={} end
return M
