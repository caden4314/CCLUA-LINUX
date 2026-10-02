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
 function api.kill(p,pid,sig)
  local t=k.process.get(pid);if not t then return nil,"ESRCH" end
  if p.uid~=0 and p.uid~=t.uid and not k.capabilities.has(p,"proc.signal")then return nil,"EPERM" end
  local n=k.signals.normalize(sig);if not n then return nil,"EINVAL" end
  t.signal=n
  if n==k.signals.names.KILL then k.process.exit(t,128+n,"killed")
  elseif n==k.signals.names.STOP then t.state="stopped"
  elseif n==k.signals.names.CONT and t.state=="stopped" then k.scheduler:wake(t.pid) end
  return true
 end
 return api
end
return M
