local vfs=dofile("/ccubuntu/lib/vfs.lua")
local M={}
local env={
 USER="caden",LOGNAME="caden",HOME="/home/caden",HOSTNAME="ccubuntu",
 SHELL="/bin/bash",TERM="xterm-256color",LANG="C.UTF-8",
 PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
}
local boot=os.clock()
local running=true

local function expand(s)
 s=s:gsub("%$%?",tostring(env["?"] or 0))
 s=s:gsub("%${([%w_]+)}",function(k)return env[k] or "" end)
 s=s:gsub("%$([%w_]+)",function(k)return env[k] or "" end)
 s=s:gsub("^~",env.HOME)
 return s
end
local function words(line)
 local out,buf={},{}; local quote=nil; local esc=false
 local function push() if #buf>0 then out[#out+1]=expand(table.concat(buf));buf={} end end
 for i=1,#line do
  local c=line:sub(i,i)
  if esc then buf[#buf+1]=c;esc=false
  elseif c=="\\" and quote~="'" then esc=true
  elseif quote then
   if c==quote then quote=nil else buf[#buf+1]=c end
  elseif c=="'" or c=='"' then quote=c
  elseif c:match("%s") then push()
  else buf[#buf+1]=c end
 end
 push(); return out
end
local function splitpipe(line)
 local out,buf={},{};local q=nil;local esc=false
 for i=1,#line do
  local c=line:sub(i,i)
  if esc then buf[#buf+1]=c;esc=false
  elseif c=="\\" then buf[#buf+1]=c;esc=true
  elseif q then buf[#buf+1]=c;if c==q then q=nil end
  elseif c=="'" or c=='"' then q=c;buf[#buf+1]=c
  elseif c=="|" then out[#out+1]=table.concat(buf);buf={}
  else buf[#buf+1]=c end
 end
 out[#out+1]=table.concat(buf);return out
end
local function human(n)
 local u={"B","K","M","G","T"};local i=1;n=tonumber(n) or 0
 while n>=1024 and i<#u do n=n/1024;i=i+1 end
 return i==1 and tostring(math.floor(n))..u[i] or string.format("%.1f%s",n,u[i])
end

local cmd={}
cmd.pwd=function() return vfs.getcwd().."\n",0 end
cmd.cd=function(a)
 local ok,e=vfs.chdir(a[2] or env.HOME);if not ok then return "bash: cd: "..(a[2] or env.HOME)..": "..e.."\n",1 end
 env.PWD=vfs.getcwd();return "",0
end
cmd.echo=function(a) return table.concat(a," ",2).."\n",0 end
cmd.printf=function(a) local f=a[2] or "";return f:gsub("\\n","\n"):gsub("\\t","\t"),0 end
cmd.clear=function() term.clear();term.setCursorPos(1,1);return "",0 end
cmd.whoami=function() return env.USER.."\n",0 end
cmd.hostname=function() return env.HOSTNAME.."\n",0 end
cmd.true=function() return "",0 end
cmd.false=function() return "",1 end
cmd.exit=function(a) running=false;return "",tonumber(a[2]) or 0 end
cmd.env=function()
 local k={};for n in pairs(env) do if n~="?" then k[#k+1]=n end end;table.sort(k)
 local o={};for _,n in ipairs(k) do o[#o+1]=n.."="..env[n] end
 return table.concat(o,"\n").."\n",0
end
cmd.export=function(a)
 for i=2,#a do local k,v=a[i]:match("^([%w_]+)=(.*)$");if k then env[k]=v end end
 return "",0
end
cmd.uname=function(a)
 local all=false;for i=2,#a do if a[i]=="-a" then all=true end end
 if all then return "Linux ccubuntu 5.15.0-ccu1-jammy #1 CCUbuntu SMP Lua x86_64 GNU/Linux\n",0 end
 return "Linux\n",0
end
cmd.lsb_release=function(a)
 if a[2]=="-a" then return "No LSB modules are available.\nDistributor ID:\tUbuntu\nDescription:\tUbuntu 22.04.5 LTS\nRelease:\t22.04\nCodename:\tjammy\n",0 end
 return "Ubuntu 22.04.5 LTS\n",0
end
cmd.id=function()
 return "uid=1000(caden) gid=1000(caden) groups=1000(caden),27(sudo)\n",0
end
cmd.date=function() return textutils.formatTime(os.time(),true).."\n",0 end
cmd.uptime=function()
 local s=math.floor(os.clock()-boot);local m=math.floor(s/60);local h=math.floor(m/60)
 return string.format(" up %d:%02d,  1 user,  load average: 0.00, 0.00, 0.00\n",h,m%60),0
end

cmd.ls=function(a)
 local long,all,path=false,false,nil
 for i=2,#a do
  if a[i]:sub(1,1)=="-" then long=long or a[i]:find("l",1,true)~=nil;all=all or a[i]:find("a",1,true)~=nil
  else path=a[i] end
 end
 path=path or "."
 if not vfs.exists(path) then return "ls: cannot access '"..path.."': No such file or directory\n",2 end
 if not vfs.isdir(path) then return (long and "-rw-r--r-- 1 caden caden "..vfs.size(path).." Sep 29 10:00 " or "")..path.."\n",0 end
 local list=vfs.list(path);table.sort(list);local o={}
 if all then o={".",".."} end
 for _,n in ipairs(list) do
  if long then
   local p=vfs.norm(path.."/"..n);local d=vfs.isdir(p)
   o[#o+1]=(d and "drwxr-xr-x" or "-rw-r--r--").." 1 caden caden "..string.format("%8d",d and 4096 or vfs.size(p)).." Sep 29 10:00 "..n
  else o[#o+1]=n end
 end
 return table.concat(o,long and "\n" or "  ").."\n",0
end
cmd.cat=function(a,stdin)
 if #a==1 then return stdin or "",0 end
 local o={}
 for i=2,#a do local s,e=vfs.read(a[i]);if not s then return "cat: "..a[i]..": "..e.."\n",1 end;o[#o+1]=s end
 return table.concat(o),0
end
cmd.mkdir=function(a)
 local parents=false
 for i=2,#a do if a[i]=="-p" then parents=true else local ok,e=vfs.mkdir(a[i],parents);if not ok then return "mkdir: "..e.."\n",1 end end end
 return "",0
end
cmd.touch=function(a)
 for i=2,#a do if not vfs.exists(a[i]) then local ok,e=vfs.write(a[i],"",false);if not ok then return "touch: "..e.."\n",1 end end end
 return "",0
end
cmd.rm=function(a)
 local rec=false
 for i=2,#a do if a[i]=="-r" or a[i]=="-rf" or a[i]=="-fr" then rec=true elseif a[i]:sub(1,1)~="-" then local ok,e=vfs.remove(a[i],rec);if not ok then return "rm: "..e.."\n",1 end end end
 return "",0
end
cmd.cp=function(a) if not a[2] or not a[3] then return "cp: missing file operand\n",1 end;vfs.copy(a[2],a[3]);return "",0 end
cmd.mv=function(a) if not a[2] or not a[3] then return "mv: missing file operand\n",1 end;vfs.move(a[2],a[3]);return "",0 end

cmd.df=function()
 local cap,free=vfs.capacity(),vfs.free();local used=math.max(0,cap-free);local pct=cap>0 and math.floor(used*100/cap) or 0
 return "Filesystem      Size  Used Avail Use% Mounted on\n/dev/ccfs       "..human(cap).."  "..human(used).."  "..human(free).."  "..pct.."% /\n",0
end
cmd.free=function()
 local total=16*1024*1024;local used=math.floor(total*.22);local free=total-used
 return "               total        used        free      shared  buff/cache   available\nMem:        "..string.format("%12s%12s%12s%12s%12s%12s",human(total),human(used),human(free),"0B","0B",human(free)).."\nSwap:                 0B          0B          0B\n",0
end
cmd.ps=function()
 return "USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND\n"..
 "root           1  0.0  0.1   4096  1024 ?        Ss   10:00   0:00 /sbin/init\n"..
 "caden        100  0.0  0.2   4096  1536 tty1     Ss   10:00   0:00 -bash\n"..
 "caden        121  0.0  0.1   2048   768 tty1     R+   10:00   0:00 ps aux\n",0
end
cmd.systemctl=function(a)
 local services={["systemd-journald.service"]="active (running)",["systemd-logind.service"]="active (running)",
  ["cron.service"]="active (running)",["dbus.service"]="active (running)",["ssh.service"]="inactive (dead)"}
 if not a[2] or a[2]=="list-units" then
  local o={"UNIT                         LOAD   ACTIVE SUB     DESCRIPTION"}
  for n,s in pairs(services) do o[#o+1]=string.format("%-28s loaded %-6s running CCUbuntu service",n,s:sub(1,6)) end
  return table.concat(o,"\n").."\n",0
 end
 if a[2]=="status" then
  local n=a[3] or "";if n~="" and not n:find("%.") then n=n..".service" end
  local s=services[n] or "inactive (dead)"
  return "%Ï "..n.." - CCUbuntu compatibility service\n     Loaded: loaded (/lib/systemd/system/"..n.."; enabled)\n     Active: "..s.."\n",s:find("^active") and 0 or 3
 end
 return "",0
end

local installed={
 {"adduser","3.118ubuntu5"},{"apt","2.4.14"},{"base-files","12ubuntu4.7"},{"bash","5.1-6ubuntu1.1"},
 {"coreutils","8.32-4.1ubuntu1.2"},{"dash","0.5.11+git20210903+057cd650a4ed-3build1"},
 {"dpkg","1.21.1ubuntu2.3"},{"grep","3.7-1build1"},{"hostname","3.23ubuntu2"},
 {"iproute2","5.15.0-1ubuntu2"},{"nano","6.2-1"},{"procps","2:3.3.17-6ubuntu2.1"},
 {"sed","4.8-1ubuntu2"},{"systemd","249.11-0ubuntu3.17"},{"util-linux","2.37.2-4ubuntu3.4"},
}
cmd.dpkg=function(a)
 if a[2]=="-l" or a[2]=="--list" then
  local o={"Desired=Unknown/Install/Remove/Purge/Hold","||/ Name           Version                    Architecture Description",
   "+++-==============-==========================-============-================================="}
  for _,p in ipairs(installed) do o[#o+1]=string.format("ii  %-14s %-26s all          CCUbuntu Jammy package",p[1],p[2]) end
  return table.concat(o,"\n").."\n",0
 end
 return "dpkg: CCUbuntu compatibility dpkg; supported: -l, --list\n",0
end
cmd.apt=function(a)
 local sub=a[2] or ""
 if sub=="update" then return "Hit:1 http://archive.ubuntu.com/ubuntu jammy InRelease\nHit:2 http://archive.ubuntu.com/ubuntu jammy-updates InRelease\nHit:3 http://security.ubuntu.com/ubuntu jammy-security InRelease\nReading package lists... Done\nBuilding dependency tree... Done\nAll packages are up to date.\n",0 end
 if sub=="list" and (a[3]=="--installed" or not a[3]) then
  local o={"Listing... Done"};for _,p in ipairs(installed) do o[#o+1]=p[1].."/jammy,now "..p[2].." all [installed]" end
  return table.concat(o,"\n").."\n",0
 end
 if sub=="install" then
  local p=a[3];if not p then return "E: No packages found\n",100 end
  return "Reading package lists... Done\nBuilding dependency tree... Done\nE: Package '"..p.."' is not yet available as a CCUbuntu Lua port\n",100
 end
 return "apt 2.4.14 (CCUbuntu compatibility)\nUsage: apt [options] command\n\nCommands: update, install, list\n",0
end
