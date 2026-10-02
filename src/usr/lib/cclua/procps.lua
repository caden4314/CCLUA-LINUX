local M={}
local function username(k,uid)
  local u=k.users.by_uid(uid)
  return (u and u.name) or tostring(uid)
end
local function matches(p,pat)
  return tostring(p.name):find(pat)~=nil or table.concat(p.argv or {}," "):find(pat)~=nil
end
local H={}
function H.pgrep(ctx,args)
  local pat=args[#args];if not pat then return 2 end
  local found=false
  for _,p in ipairs(ctx.kernel.process.all())do if matches(p,pat)then print(p.pid);found=true end end
  return found and 0 or 1
end
function H.pkill(ctx,args)
  local sig="TERM";local pat=nil
  for _,a in ipairs(args)do if a:sub(1,1)=="-" then sig=a:sub(2)else pat=a end end
  if not pat then return 2 end
  local n=0
  for _,p in ipairs(ctx.kernel.process.all())do
    if p.pid~=ctx.process.pid and matches(p,pat)then
      local ok=ctx.kernel.syscalls.kill(ctx.process,p.pid,sig);if ok then n=n+1 end
    end
  end
  return n>0 and 0 or 1
end
function H.pwdx(ctx,args)
  local rc=0
  for _,a in ipairs(args)do local p=ctx.kernel.process.get(tonumber(a));if p then print(p.pid..": "..p.cwd)else print(a..": No such process");rc=1 end end
  return rc
end
function H.pmap(ctx,args)
  local p=ctx.kernel.process.get(tonumber(args[1]));if not p then print("pmap: argument missing or invalid");return 1 end
  print(p.pid..":   "..table.concat(p.argv or {p.name}," "))
  print(" Address           Kbytes Mode  Mapping")
  print(" 00000000              0 r-x-- lua-coroutine")
  print(" total                 0K")
  return 0
end
function H.vmstat(ctx,args)
  print("procs -----------memory---------- ---system-- ------cpu-----")
  print(" r  b   swpd   free   buff  cache   in   cs us sy id wa st")
  local r=0
  for _,p in ipairs(ctx.kernel.process.all())do if p.state=="runnable" or p.state=="running" then r=r+1 end end
  print(("%2d  0      0      0      0      0    0    0  0  0 100  0  0"):format(r))
  return 0
end
function H.w(ctx,args)
  print((" %s up %.0f sec,  1 user,  load average: 0.00, 0.00, 0.00"):format(os.date and os.date("%H:%M:%S") or "",os.clock()))
  print("USER     TTY      FROM             LOGIN@   IDLE   JCPU   PCPU WHAT")
  print(("%-8s tty1     -                -        0.00s  0.00s  0.00s bash"):format(username(ctx.kernel,ctx.process.uid)))
  return 0
end
function H.watch(ctx,args)
  local interval=2;local cmd={};local i=1
  while i<=#args do if args[i]=="-n" and args[i+1]then interval=tonumber(args[i+1])or 2;i=i+2 else cmd[#cmd+1]=args[i];i=i+1 end end
  if #cmd==0 then return 1 end
  print("watch: continuous command execution is limited; running once in CCLUA 0.2")
  print("Every "..interval.."s: "..table.concat(cmd," "))
  return 0
end
function H.tload(ctx,args)
  print("tload: load average 0.00 (CCLUA cooperative scheduler)")
  return 0
end
function H.pidwait(ctx,args)
  local pid=tonumber(args[1]);if not pid then return 2 end
  local p=ctx.kernel.process.get(pid);if not p then return 1 end
  while p.state~="exited" and p.state~="killed" and p.state~="crashed" do coroutine.yield("wait_event","cclua_process_exit") end
  return 0
end
function M.run(name,ctx,args)
  local f=H[name];if not f then print(name..": not implemented");return 127 end
  return f(ctx,args or {})
end
return M
