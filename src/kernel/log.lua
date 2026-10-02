local M={}; local ring={}; local max=256
local function now() return (os and os.epoch and os.epoch("utc")) or 0 end
function M.write(level,subsystem,message,details,pid)
 local r={timestamp=now(),level=level or "info",subsystem=subsystem or "kernel",pid=pid,message=tostring(message or ""),details=details}
 ring[#ring+1]=r; if #ring>max then table.remove(ring,1) end; return r
end
function M.entries() local o={} for i,v in ipairs(ring) do o[i]=v end return o end
function M.clear() ring={} end
return M
