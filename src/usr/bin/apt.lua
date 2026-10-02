local config=dofile("/usr/lib/cclua/config.lua")
local function db()
 local h=fs.open("usr/share/cclua/ubuntu-server-packages.json","r")
 if not h then return {packages={}} end
 local raw=h.readAll();h.close()
 return textutils.unserializeJSON(raw) or {packages={}}
end
local function findpkg(name)
 for _,p in ipairs(db().packages or {}) do if p.name==name then return p end end
end
return {main=function(ctx,args)
 local cmd=args[1] or "help"
 if cmd=="list" then
  for _,p in ipairs(db().packages or {}) do print(("%s/jammy,now %s amd64 [installed]"):format(p.name,p.version or "?")) end
  return 0
 elseif cmd=="show" then
  local name=args[2];if not name then print("E: No packages found");return 100 end
  local p=findpkg(name);if not p then print("N: Unable to locate package "..name);return 100 end
  print("Package: "..p.name);print("Version: "..(p.version or "?"));print("Architecture: amd64");print("Status: installed");print("Source: Ubuntu 22.04.5 Server manifest")
  return 0
 elseif cmd=="search" then
  local q=(args[2] or ""):lower()
  for _,p in ipairs(db().packages or {}) do if p.name:lower():find(q,1,true) then print(("%s/jammy %s"):format(p.name,p.version or "?")) end end
  return 0
 elseif cmd=="update" then
  print("Hit:1 CCLUA manager development jammy InRelease")
  print("Reading package lists... Done")
  print("Building dependency tree... Done")
  print("All packages are up to date.")
  return 0
 elseif cmd=="upgrade" then
  print("Reading package lists... Done")
  print("Building dependency tree... Done")
  print("Calculating upgrade... Done")
  print("0 upgraded, 0 newly installed, 0 to remove.")
  return 0
 elseif cmd=="install" or cmd=="remove" then
  print("E: package mutation is not enabled yet in CCLUA 0.1")
  print("   Package database is real Ubuntu 22.04.5 Server data; installer backend is still under construction.")
  return 100
 end
 print("apt 2.4.14 (cclua)")
 print("Usage: apt list|show|search|update|upgrade")
 return 0
end}
