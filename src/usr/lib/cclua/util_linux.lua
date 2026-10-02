local M={}
local H={}

function H.lscpu(ctx,args)
  print("Architecture:                         cclua")
  print("CPU op-mode(s):                       Lua")
  print("Byte Order:                           Little Endian")
  print("CPU(s):                               1")
  print("On-line CPU(s) list:                  0")
  print("Vendor ID:                            CC:Tweaked")
  print("Model name:                           Lua coroutine scheduler")
  print("Virtualization:                       ComputerCraft")
  return 0
end

function H.lsmem(ctx,args)
  print("RANGE                                  SIZE  STATE")
  print("0x0000000000000000-0x0000000000000000 dynamic online")
  print("")
  print("Memory block size: dynamic")
  print("Total online memory: CC:Tweaked managed")
  return 0
end

function H.lsipc(ctx,args)
  print("RESOURCE DESCRIPTION                         LIMIT USED USE%")
  print(("MSGMNI   message queues                       dynamic %d    -"):format(#ctx.kernel.process.all()))
  print("SHMMNI   shared memory segments                0       0    0%")
  print("SEMMNI   semaphore identifiers                 0       0    0%")
  return 0
end

function H.lslocks(ctx,args)
  print("COMMAND           PID  TYPE SIZE MODE M START END PATH")
  return 0
end

function H.lsns(ctx,args)
  print("NS TYPE   NPROCS PID USER COMMAND")
  print(("1  cclua  %d     1 root /sbin/init"):format(#ctx.kernel.process.all()))
  return 0
end

function H.lslogins(ctx,args)
  print(" UID USER          PROC PWD-LOCK PWD-DENY LAST-LOGIN")
  local arr={}
  for _,u in pairs(ctx.kernel.users.all()) do arr[#arr+1]=u end
  table.sort(arr,function(a,b)return a.uid<b.uid end)
  for _,u in ipairs(arr) do
    local procs=0
    for _,p in ipairs(ctx.kernel.process.all())do if p.uid==u.uid then procs=procs+1 end end
    print(("%4d %-13s %4d        0        0 -"):format(u.uid,u.name,procs))
  end
  return 0
end

function H.whereis(ctx,args)
  for _,name in ipairs(args)do
    local p=ctx.kernel.exec.resolve(name)
    print(name..":"..(p and (" "..p) or ""))
  end
  return 0
end

function H.rev(ctx,args)
  local function rev(s)return s:reverse()end
  if #args==0 then
    local l=read();if l then print(rev(l))end
    return 0
  end
  for _,file in ipairs(args)do
    local p=file;if p:sub(1,1)~="/" then p=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..p)end
    local h,e=ctx.kernel.vfs.open(p,"r")
    if not h then print("rev: "..tostring(e));return 1 end
    local d=h.readAll and h.readAll() or "";if h.close then h.close()end
    for line in (d.."\n"):gmatch("(.-)\n")do print(rev(line))end
  end
  return 0
end

function H.getopt(ctx,args)
  print(table.concat(args," "))
  return 0
end

function H.setarch(ctx,args)
  if #args==0 then print("cclua");return 0 end
  print("setarch: personality changes are not required on CCLUA")
  return 0
end

function H.taskset(ctx,args)
  if #args==0 then print("taskset: missing operand");return 1 end
  local pid=tonumber(args[#args])
  if pid then
    local p=ctx.kernel.process.get(pid)
    if not p then print("taskset: failed to get pid "..pid..": No such process");return 1 end
    print(("pid %d's current affinity mask: 1"):format(pid));return 0
  end
  print("taskset: CCLUA has one cooperative execution lane")
  return 0
end

function H.ionice(ctx,args)
  print("none: prio 0")
  return 0
end

function H.chrt(ctx,args)
  local pid=tonumber(args[#args])
  if pid then
    local p=ctx.kernel.process.get(pid);if not p then return 1 end
    print(("pid %d's current scheduling policy: SCHED_OTHER"):format(pid))
    print(("pid %d's current scheduling priority: %d"):format(pid,p.priority or 0))
    return 0
  end
  print("chrt: CCLUA cooperative scheduler");return 0
end

function H.prlimit(ctx,args)
  local pid=tonumber(args[#args]) or ctx.process.pid
  local p=ctx.kernel.process.get(pid);if not p then return 1 end
  print("RESOURCE   DESCRIPTION                  SOFT      HARD")
  print("NOFILE     max number of open files     dynamic   dynamic")
  print("NPROC      max number of processes      dynamic   dynamic")
  return 0
end

function H.last(ctx,args)
  print("root     tty1                          still logged in")
  return 0
end

function H.mesg(ctx,args)
  print("is y")
  return 0
end

function H.setsid(ctx,args)
  print("setsid: process-group/session emulation is kernel-managed")
  return 0
end

function M.run(name,ctx,args)
  local f=H[name]
  if not f then print(name..": not implemented");return 127 end
  return f(ctx,args or {})
end
return M
