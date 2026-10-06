local M={}
local config=dofile("/usr/lib/cclua/config.lua")

local packageProvides={
  ["cclua-runtime"]={"cclua","cclua-status","cclua-doctor","fastfetch"},
  ["cclua-drivers"]={"driverctl","cclua-peripheralctl","peripherals"},
  ["cclua-network"]={"ip","ss","ping","networkctl","resolvectl","cclua-net"},
  ["cclua-services"]={"systemctl","service","journalctl","dmesg","systemd-analyze"},
  ["cclua-apphost"]={"cclua-appctl"},
  ["apt"]={"apt"},
  ["dpkg"]={"dpkg"},
  ["bash"]={"bash","sh"},
  ["coreutils"]={
    "basename","cat","cp","date","df","dirname","du","echo","env","false",
    "head","hostid","hostname","id","ls","mkdir","mv","nproc","printenv",
    "printf","pwdx","realpath","rm","seq","sleep","sort","stat","tail","tee",
    "touch","tr","true","truncate","tty","uname","uniq","unlink","uptime",
    "users","wc","whoami","yes"
  },
  ["grep"]={"grep"},
  ["sed"]={"sed"},
  ["gawk"]={"awk"},
  ["findutils"]={"find","xargs"},
  ["curl"]={"curl"},
  ["wget"]={"wget"},
  ["util-linux"]={
    "arch","blkid","chrt","findmnt","getopt","ionice","last","lsblk","lscpu",
    "lsipc","lslocks","lslogins","lsmem","lsns","mesg","mount","nice",
    "prlimit","setarch","setsid","taskset","umount","whereis"
  },
  ["procps"]={"free","pgrep","pidwait","pkill","pmap","ps","tload","top","vmstat","w","watch"},
  ["iproute2"]={"ip","ss"},
  ["iputils-ping"]={"ping"},
  ["systemd"]={"hostnamectl","localectl","networkctl","systemctl","timedatectl"},
  ["sudo"]={"sudo","su"},
  ["passwd"]={"passwd","useradd","userdel","groupadd","groupdel","groups"},
  ["less"]={"less"},
}

local function role()
  local m=config.machine()
  local image=tostring(m.image or "")
  if m.role=="desktop-client" or image:find("desktop",1,true) then return "desktop" end
  return "server"
end

local function host(path)
  return tostring(path):gsub("^/","")
end

local function command_exists(name)
  if type(fs)~="table" or type(fs.exists)~="function" then return false end
  return fs.exists(host("/usr/bin/"..tostring(name)..".lua"))
end

local function reference_path()
  if role()=="desktop" then
    return "/usr/share/cclua/ubuntu-desktop-packages.json"
  end
  return "/usr/share/cclua/ubuntu-server-packages.json"
end

local function load_reference()
  if type(fs)~="table" or type(fs.open)~="function" then
    return {schema=1,role=role(),packages={}}
  end
  local path=host(reference_path())
  local h=fs.open(path,"r")
  if not h then return {schema=1,role=role(),packages={}} end
  local raw=h.readAll();h.close()
  local ok,data=pcall(textutils.unserializeJSON,raw)
  if not ok or type(data)~="table" then
    return {schema=1,role=role(),packages={}}
  end
  return data
end

local function ref_index()
  local map={}
  for _,p in ipairs(load_reference().packages or {}) do map[p.name]=p end
  return map
end

local function implemented_entry(name,commands,refs)
  local present={}
  for _,cmd in ipairs(commands or {}) do
    if command_exists(cmd) then present[#present+1]=cmd end
  end
  if #present==0 then return nil end
  local ref=refs[name] or {}
  return {
    name=name,
    version=ref.version or "cclua-0.2",
    architecture="lua",
    source="CCLUA native implementation",
    implementation="native",
    installed=true,
    commands=present,
    reference_version=ref.version,
  }
end

function M.role() return role() end
function M.path() return reference_path() end

function M.reference()
  return load_reference()
end

function M.implemented()
  local refs=ref_index()
  local out={}
  for name,commands in pairs(packageProvides) do
    local p=implemented_entry(name,commands,refs)
    if p then out[#out+1]=p end
  end
  if role()=="desktop" then
    local commands={"cclua-desktop","gnome-shell","gnome-terminal","nautilus"}
    local p=implemented_entry("cclua-desktop",commands,refs)
    if p then out[#out+1]=p end
  end
  table.sort(out,function(a,b)return a.name<b.name end)
  return out
end

function M.load()
  local ref=load_reference()
  local implemented={}
  for _,p in ipairs(M.implemented()) do implemented[p.name]=p end
  local packages={}
  for _,p in ipairs(ref.packages or {}) do
    local native=implemented[p.name]
    packages[#packages+1]={
      name=p.name,version=p.version,
      implementation=native and "native" or "reference",
      installed=native~=nil,
      commands=native and native.commands or nil,
      architecture=native and "lua" or "amd64",
    }
  end
  for name,p in pairs(implemented) do
    local exists=false
    for _,r in ipairs(ref.packages or {}) do if r.name==name then exists=true;break end end
    if not exists then packages[#packages+1]=p end
  end
  table.sort(packages,function(a,b)return a.name<b.name end)
  return {
    schema=2,distribution=ref.distribution or "Ubuntu",
    release=ref.release or "22.04.5",role=role(),
    package_count=#packages,packages=packages,
    implemented_count=#M.implemented(),
    reference_count=#(ref.packages or {}),
  }
end

function M.find(name)
  name=tostring(name or "")
  for _,p in ipairs(M.implemented()) do if p.name==name then return p end end
  for _,p in ipairs(load_reference().packages or {}) do
    if p.name==name then
      return {
        name=p.name,version=p.version,architecture="amd64",
        implementation="reference",installed=false,
        source="Ubuntu 22.04.5 reference manifest",
      }
    end
  end
end

function M.search(query,opts)
  opts=opts or {}
  local q=tostring(query or ""):lower()
  local out={}
  for _,p in ipairs(M.load().packages or {}) do
    if (q=="" or tostring(p.name):lower():find(q,1,true))
      and (not opts.implemented_only or p.implementation=="native") then
      out[#out+1]=p
    end
  end
  table.sort(out,function(a,b)
    if a.implementation~=b.implementation then return a.implementation=="native" end
    return a.name<b.name
  end)
  return out
end

function M.status(name)
  local p=M.find(name)
  if not p then return nil,"package not found" end
  return {
    name=p.name,version=p.version,installed=p.installed==true,
    implementation=p.implementation or "reference",
    architecture=p.architecture or "lua",
    commands=p.commands or {},source=p.source,
  }
end

return M
