local RELEASE = { id="ubuntu", version="22.04.5", codename="jammy", pretty="Ubuntu 22.04.5 LTS" }
local KERNEL = "5.15.0-cc-tweaked-jammy"
local ROOT, STATE = "/ccubuntu/root", "/ccubuntu/state"
local USER, HOST, HOME = "caden", "ccubuntu", "/home/caden"
local cwd, running, bootClock = HOME, true, os.clock()
local env = {
 HOME=HOME, USER=USER, LOGNAME=USER, SHELL="/bin/bash", TERM="xterm-256color",
 PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
 LANG="C.UTF-8", PWD=HOME, HOSTNAME=HOST,
}
local C={white=colors.white,dim=colors.gray,blue=colors.lightBlue,cyan=colors.cyan,
 green=colors.lime,yellow=colors.yellow,red=colors.red,purple=colors.purple}
local function col(c) if term.isColor() then term.setTextColor(c) end end
local function out(s,c) if c then col(c) end print(s or "") col(C.white) end
local function trim(s) return (tostring(s or ""):gsub("^%s+",""):gsub("%s+$","")) end
local function norm(path)
 path=tostring(path or ""); if path=="" then return cwd end
 if path=="~" then return HOME elseif path:sub(1,2)=="~/" then path=HOME..path:sub(2) end
 if path:sub(1,1)~="/" then path=cwd.."/"..path end
 local a={}
 for p in path:gmatch("[^/]+") do
  if p==".." then table.remove(a) elseif p~="." and p~="" then a[#a+1]=p end
 end
 return "/"..table.concat(a,"/")
end
local function hp(path) local p=norm(path); return p=="/" and ROOT or ROOT..p end
local function exists(p) return fs.exists(hp(p)) end
local function isdir(p) return fs.isDir(hp(p)) end
local function mkdir(p) local q=hp(p); if not fs.exists(q) then fs.makeDir(q) end end
local function readfile(p)
 local h=fs.open(hp(p),"r"); if not h then return nil end
 local s=h.readAll(); h.close(); return s
end
local function writefile(p,s,append)
 local q=hp(p); local d=fs.getDir(q); if d~="" and not fs.exists(d) then fs.makeDir(d) end
 local h=fs.open(q,append and "a" or "w"); if not h then return false end
 h.write(s or ""); h.close(); return true
end
local function initfs()
 for _,p in ipairs({"/bin","/boot","/dev","/etc","/etc/apt","/etc/systemd/system","/home",
  HOME,"/lib","/lib64","/media","/mnt","/opt","/proc","/root","/run","/sbin","/srv","/sys",
  "/tmp","/usr","/usr/bin","/usr/lib","/usr/sbin","/usr/share","/var","/var/cache/apt",
  "/var/lib/dpkg","/var/log","/var/tmp"}) do mkdir(p) end
 writefile("/etc/os-release",'PRETTY_NAME="Ubuntu 22.04.5 LTS"\nNAME="Ubuntu"\nVERSION_ID="22.04"\n'..
  'VERSION="22.04.5 LTS (Jammy Jellyfish)"\nVERSION_CODENAME=jammy\nID=ubuntu\nID_LIKE=debian\n'..
  'HOME_URL="https://www.ubuntu.com/"\nSUPPORT_URL="https://help.ubuntu.com/"\n',false)
 writefile("/etc/hostname",HOST.."\n",false)
 writefile("/etc/hosts","127.0.0.1 localhost\n127.0.1.1 "..HOST.."\n::1 localhost ip6-localhost ip6-loopback\n",false)
 writefile("/etc/passwd","root:x:0:0:root:/root:/bin/bash\n"..USER..":x:1000:1000:Caden,,,:/home/"..USER..":/bin/bash\n",false)
 writefile("/etc/group","root:x:0:\nsudo:x:27:"..USER.."\n"..USER..":x:1000:\n",false)
end
