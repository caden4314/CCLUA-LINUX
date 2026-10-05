local M={}
local next_pid=2
local bypid={}
local terminal_states={exited=true,killed=true,crashed=true}

local function alloc()
  while bypid[next_pid] do next_pid=next_pid+1 end
  local pid=next_pid
  next_pid=next_pid+1
  return pid
end

function M.create(o)
  o=o or {}
  local pid=o.pid or alloc()
  if bypid[pid] then return nil,"EEXIST" end
  local pty=o.pty
  local p={
    pid=pid,ppid=o.ppid or 0,name=o.name or ("process-"..pid),state="new",
    uid=o.uid or 0,gid=o.gid or 0,groups=o.groups or {},
    session_id=o.session_id or pid,process_group=o.process_group or pid,
    cwd=o.cwd or "/",environment=o.environment or {},argv=o.argv or {},
    capabilities=o.capabilities or {},priority=o.priority or 0,
    created_at=(os.epoch and os.epoch("utc") or 0),started_at=nil,ended_at=nil,
    exit_code=nil,signal=nil,open_handles={},mailbox={},coroutine=nil,
    event_filter=nil,wake_at=nil,cpu_resumes=0,error=nil,
    pending_events={},resume_event=nil,stopped_state=nil,stopped_filter=nil,
    pty=pty,terminal=o.terminal or (pty and pty.term) or nil,
    stdin=o.stdin or (pty and pty.stdin) or nil,
    stdout=o.stdout or (pty and pty.stdout) or nil,
    stderr=o.stderr or (pty and pty.stderr) or nil,
    fd=o.fd or {},owned_streams=o.owned_streams or {},
    job_id=o.job_id,background=o.background==true,
  }
  p.fd[0]=p.fd[0] or p.stdin
  p.fd[1]=p.fd[1] or p.stdout
  p.fd[2]=p.fd[2] or p.stderr
  bypid[pid]=p
  return p
end

function M.get(pid)
  return bypid[tonumber(pid)]
end

function M.all()
  local out={}
  for _,p in pairs(bypid) do out[#out+1]=p end
  table.sort(out,function(a,b) return a.pid<b.pid end)
  return out
end
function M.children(ppid)
  local out={}
  for _,p in pairs(bypid) do
    if p.ppid==tonumber(ppid) then out[#out+1]=p end
  end
  table.sort(out,function(a,b) return a.pid<b.pid end)
  return out
end

function M.group(pgid)
  local out={}
  for _,p in pairs(bypid) do
    if p.process_group==tonumber(pgid) then out[#out+1]=p end
  end
  table.sort(out,function(a,b) return a.pid<b.pid end)
  return out
end

function M.is_terminal(p)
  return not p or terminal_states[p.state]==true
end

function M.exit(p,code,state)
  if not p or terminal_states[p.state] then return false end
  p.state=state or "exited"
  p.exit_code=tonumber(code) or 0
  p.ended_at=(os.epoch and os.epoch("utc") or 0)
  p.event_filter=nil
  p.wake_at=nil
  if not p.streams_closed then
    p.streams_closed=true
    for _,stream in ipairs(p.owned_streams or {}) do
      if stream and stream.close then pcall(stream.close,stream) end
    end
  end
  return true
end

function M.set_group(pid,pgid)
  local p=M.get(pid)
  if not p then return nil,"ESRCH" end
  p.process_group=tonumber(pgid) or p.pid
  return true
end

function M.remove(pid)
  bypid[tonumber(pid)]=nil
end

return M
