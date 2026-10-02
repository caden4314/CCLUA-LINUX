local M={}
function M.waitEvent(f)return coroutine.yield("wait_event",f)end
function M.sleep(sec)local now=(os.epoch and os.epoch("utc"))or 0;return coroutine.yield("sleep",now+math.floor((sec or 0)*1000))end
return M
