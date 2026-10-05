local M={}
function M.new(k)
 local api={}
 function api.getpid(p)return p.pid end
 function api.getppid(p)return p.ppid end
 function api.getuid(p)return p.uid end
 function api.getgid(p)return p.gid end
 function api.list_processes(p)
  if p.uid~=0 and not k.capabilities.has(p,"proc.inspect")then return nil,"EPERM" end
  return k.process.all()
 end
 local function signal_one(p,t,n)
  if p.uid~=0 and p.uid~=t.uid and not k.capabilities.has(p,"proc.signal") then return nil,"EPERM" end
  t.signal=n
  if n==k.signals.names.STOP then
   if not k.process.is_terminal(t) then
    t.stopped_state=t.state
    t.stopped_filter=t.event_filter
    t.state="stopped"
   end
  elseif n==k.signals.names.CONT then
   if t.state=="stopped" then
    t.state=t.stopped_state or "waiting"
    t.event_filter=t.stopped_filter
    t.stopped_state=nil
    t.stopped_filter=nil
    if t.state=="runnable" then k.scheduler:wake(t.pid) end
   end
  elseif n==k.signals.names.KILL or n==k.signals.names.INT
      or n==k.signals.names.TERM or n==k.signals.names.HUP then
   local changed=k.process.exit(t,128+n,"killed")
   if changed and os.queueEvent then os.queueEvent("cclua_process_exit",t.pid,t.exit_code,"killed") end
  end
  return true
 end
 function api.kill(p,pid,sig)
  local t=k.process.get(pid);if not t then return nil,"ESRCH" end
  local n=k.signals.normalize(sig);if not n then return nil,"EINVAL" end
  return signal_one(p,t,n)
 end
 function api.kill_group(p,pgid,sig)
  local n=k.signals.normalize(sig);if not n then return nil,"EINVAL" end
  local group=k.process.group(pgid)
  if #group==0 then return nil,"ESRCH" end
  for _,t in ipairs(group) do
   local ok,err=signal_one(p,t,n)
   if not ok then return nil,err end
  end
  return true
 end
 return api
end
return M
