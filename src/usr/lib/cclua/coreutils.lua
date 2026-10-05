local M={}
local stdio=dofile("/usr/lib/cclua/stdio.lua")

local function abspath(ctx,p)
  p=p or ctx.process.cwd
  if p:sub(1,1)~="/" then p=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..p) end
  return ctx.kernel.vfs.normalize(p)
end

local function readall(ctx,p)
  p=abspath(ctx,p)
  local h,e=ctx.kernel.vfs.open(p,"r")
  if not h then return nil,e end
  local d=h.readAll and h.readAll() or ""
  if h.close then h.close() end
  return d
end

local function writeall(ctx,p,data,mode)
  p=abspath(ctx,p)
  local h,e=ctx.kernel.vfs.open(p,mode or "w")
  if not h then return nil,e end
  h.write(data)
  if h.close then h.close() end
  return true
end

local function readsource(ctx,p)
  if not p or p=="-" then return stdio.read_all(ctx) end
  return readall(ctx,p)
end

local handlers={}

function handlers.basename(ctx,args)
  local p=args[1];if not p then return 1 end
  p=p:gsub("/+$","")
  print(p:match("([^/]+)$") or p)
  return 0
end

function handlers.dirname(ctx,args)
  local p=args[1];if not p then return 1 end
  p=p:gsub("/+$","")
  local d=p:match("^(.*)/[^/]*$") or "."
  if d=="" then d="/" end
  print(d);return 0
end

function handlers.realpath(ctx,args)
  if not args[1] then return 1 end
  print(abspath(ctx,args[1]));return 0
end

function handlers.arch() print("cclua");return 0 end
function handlers.nproc() print("1");return 0 end
function handlers.hostid()
  local id=os.getComputerID and os.getComputerID() or 0
  print(("%08x"):format(id));return 0
end

function handlers.printenv(ctx,args)
  if #args==0 then
    local k={}for n in pairs(ctx.process.environment or {})do k[#k+1]=n end;table.sort(k)
    for _,n in ipairs(k)do print(n.."="..tostring(ctx.process.environment[n]))end
    return 0
  end
  local rc=0
  for _,n in ipairs(args)do local v=ctx.process.environment[n];if v~=nil then print(v)else rc=1 end end
  return rc
end

function handlers.printf(ctx,args)
  if not args[1] then return 0 end
  local fmt=args[1]:gsub("\\n","\n"):gsub("\\t","\t")
  local vals={}
  for i=2,#args do vals[#vals+1]=tonumber(args[i]) or args[i] end
  local ok,s=pcall(string.format,fmt,table.unpack(vals))
  if not ok then write(fmt);return 1 end
  write(s);return 0
end

function handlers.seq(ctx,args)
  local first,step,last
  if #args==1 then first,step,last=1,1,tonumber(args[1])
  elseif #args==2 then first,step,last=tonumber(args[1]),1,tonumber(args[2])
  else first,step,last=tonumber(args[1]),tonumber(args[2]),tonumber(args[3]) end
  if not first or not step or not last or step==0 then return 1 end
  local i=first
  if step>0 then while i<=last do print(i);i=i+step end else while i>=last do print(i);i=i+step end end
  return 0
end

function handlers.sort(ctx,args)
  local p=args[#args]
  local d,e=readsource(ctx,p);if not d then stdio.errorln(ctx,"sort: "..tostring(e));return 1 end
  local lines={}for line in (d.."\n"):gmatch("(.-)\n")do lines[#lines+1]=line end
  table.sort(lines)
  for _,l in ipairs(lines)do print(l)end
  return 0
end

function handlers.uniq(ctx,args)
  local p=args[#args]
  local d,e=readsource(ctx,p);if not d then stdio.errorln(ctx,"uniq: "..tostring(e));return 1 end
  local prev=nil
  for line in (d.."\n"):gmatch("(.-)\n")do if line~=prev then print(line);prev=line end end
  return 0
end

function handlers.cut(ctx,args)
  local delim="\t";local field=nil;local file=nil;local i=1
  while i<=#args do
    if args[i]=="-d" and args[i+1] then delim=args[i+1];i=i+2
    elseif args[i]=="-f" and args[i+1] then field=tonumber(args[i+1]);i=i+2
    else file=args[i];i=i+1 end
  end
  if not field then return 1 end
  local d,e=readsource(ctx,file);if not d then stdio.errorln(ctx,"cut: "..tostring(e));return 1 end
  for line in (d.."\n"):gmatch("(.-)\n")do
    local parts={}for x in (line..delim):gmatch("(.-)"..delim)do parts[#parts+1]=x end
    print(parts[field] or "")
  end
  return 0
end

function handlers.tee(ctx,args)
  local append=false;local file=nil
  for _,a in ipairs(args)do if a=="-a" then append=true else file=a end end
  if not file then return 1 end
  local lines={}
  while true do local l=stdio.read_line(ctx);if l==nil then break end;lines[#lines+1]=l;print(l)end
  local data=table.concat(lines,"\n")..(#lines>0 and "\n" or "")
  local ok,e=writeall(ctx,file,data,append and "a" or "w");if not ok then print("tee: "..tostring(e));return 1 end
  return 0
end

function handlers.tr(ctx,args)
  if #args<2 then return 1 end
  local from,to=args[1],args[2]
  local map={}
  for i=1,#from do map[from:sub(i,i)]=to:sub(math.min(i,#to),math.min(i,#to)) end
  while true do
    local l=stdio.read_line(ctx);if l==nil then break end
    print((l:gsub(".",function(c)return map[c] or c end)))
  end
  return 0
end

function handlers.truncate(ctx,args)
  local size=0;local file=nil;local i=1
  while i<=#args do
    if args[i]=="-s" and args[i+1] then size=tonumber(args[i+1]) or 0;i=i+2 else file=args[i];i=i+1 end
  end
  if not file then return 1 end
  local d=readall(ctx,file) or ""
  if #d>size then d=d:sub(1,size) elseif #d<size then d=d..string.rep("\0",size-#d) end
  local ok,e=writeall(ctx,file,d,"w");if not ok then print("truncate: "..tostring(e));return 1 end
  return 0
end

function handlers.stat(ctx,args)
  local p=args[#args];if not p then return 1 end
  p=abspath(ctx,p);local st,e=ctx.kernel.vfs.stat(p);if not st then print("stat: "..tostring(e));return 1 end
  print("  File: "..p)
  print("  Size: "..tostring(st.size or 0))
  print("  Type: "..(st.isDir and "directory" or "regular file"))
  print("Access: "..(st.readOnly and "0444" or "0644"))
  return 0
end

local function dusize(ctx,p)
  local st=ctx.kernel.vfs.stat(p);if not st then return 0 end
  if not st.isDir then return st.size or 0 end
  local n=0
  for _,x in ipairs(ctx.kernel.vfs.list(p) or {})do n=n+dusize(ctx,(p=="/" and "/" or p.."/")..x)end
  return n
end
function handlers.du(ctx,args)
  local p=abspath(ctx,args[#args] or ".")
  print(("%d\t%s"):format(math.ceil(dusize(ctx,p)/1024),p));return 0
end

function handlers.unlink(ctx,args)
  if not args[1] then return 1 end
  local p=abspath(ctx,args[1]);local ok,e=ctx.kernel.vfs.delete(p)
  if not ok then print("unlink: "..tostring(e));return 1 end
  return 0
end

function handlers.tty() print("/dev/tty");return 0 end
function handlers.logname(ctx) local u=ctx.kernel.users.by_uid(ctx.process.uid);print((u and u.name) or tostring(ctx.process.uid));return 0 end
function handlers.users(ctx) handlers.logname(ctx);return 0 end
function handlers.groups(ctx)
  local u=ctx.kernel.users.by_uid(ctx.process.uid);local name=(u and u.name) or tostring(ctx.process.uid)
  print(name);return 0
end
function handlers.nice(ctx,args)
  local cmd=args[1];if not cmd then print(tostring(ctx.process.priority or 0));return 0 end
  return 0
end
function handlers.yes(ctx,args)
  local s=#args>0 and table.concat(args," ") or "y"
  for i=1,256 do print(s) end
  return 0
end

function M.run(name,ctx,args)
  local f=handlers[name]
  if not f then print(name..": not implemented");return 127 end
  return f(ctx,args or {})
end
return M
