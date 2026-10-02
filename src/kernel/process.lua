local M={}; local next_pid=2; local bypid={}
local function alloc() while bypid[next_pid] do next_pid=next_pid+1 end local p=next_pid; next_pid=next_pid+1; return p end
function M.create(o)
 o=o or {}; local pid=o.pid or alloc(); if bypid[pid] then return nil,"EEXIST" end
 local p={pid=pid,ppid=o.ppid or 0,name=o.name or ("process-"..pid),state="new",uid=o.uid or 0,gid=o.gid or 0,groups=o.groups or {},session_id=o.session_id or pid,process_group=o.process_group or pid,cwd=o.cwd or "/",environment=o.environment or {},argv=o.argv or {},capabilities=o.capabilities or {},priority=o.priority or 0,created_at=(os.epoch and os.epoch("utc") or 0),started_at=nil,ended_at=nil,exit_code=nil,signal=nil,open_handles={},mailbox={},coroutine=nil,event_filter=nil,wake_at=nil,cpu_resumes=0,error=nil}
 bypid[pid]=p; return p
end
function M.get(pid) return bypid[tonumber(pid)] end
function M.all() local o={} for _,p in pairs(bypid) do o[#o+1]=p end table.sort(o,function(a,b)return a.pid<b.pid end); return o end
function M.exit(p,code,state) p.state=state or "exited"; p.exit_code=code or 0; p.ended_at=(os.epoch and os.epoch("utc") or 0) end
function M.remove(pid) bypid[pid]=nil end
return M
