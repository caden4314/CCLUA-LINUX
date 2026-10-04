local pkgdb=dofile("/usr/lib/cclua/package_db.lua")

local function db()
  return pkgdb.load()
end

local function findpkg(name)
  return pkgdb.find(name)
end

return {main=function(ctx,args)
  local cmd=args[1] or "help"
  local meta=db()
  local role=meta.role or pkgdb.role()
  local sourceRole=role=="desktop" and "Desktop" or "Server"

  if cmd=="list" then
    for _,p in ipairs(meta.packages or {}) do
      print(("%s/jammy,now %s amd64 [installed]"):format(p.name,p.version or "?"))
    end
    return 0
  elseif cmd=="show" then
    local name=args[2]
    if not name then print("E: No packages found");return 100 end
    local p=findpkg(name)
    if not p then print("N: Unable to locate package "..name);return 100 end
    print("Package: "..p.name)
    print("Version: "..(p.version or "?"))
    print("Architecture: amd64")
    print("Status: installed")
    print("Source: Ubuntu 22.04.5 "..sourceRole.." manifest")
    return 0
  elseif cmd=="search" then
    local q=(args[2] or ""):lower()
    for _,p in ipairs(meta.packages or {}) do
      if p.name:lower():find(q,1,true) then
        print(("%s/jammy %s"):format(p.name,p.version or "?"))
      end
    end
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
    print(("   Package database uses Ubuntu 22.04.5 %s reference data; installer backend is still under construction."):format(sourceRole))
    return 100
  end

  print("apt 2.4.14 (cclua)")
  print("Usage: apt list|show|search|update|upgrade")
  return 0
end}
