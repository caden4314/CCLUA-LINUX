local pkgdb=dofile("/usr/lib/cclua/package_db.lua")

local function usage()
  print("apt 2.4.14 (cclua)")
  print("Usage:")
  print("  apt list [--all-reference]")
  print("  apt show <package>")
  print("  apt search <text>")
  print("  apt update|upgrade")
  print("  apt install|remove <package>")
end

return {main=function(ctx,args)
  local cmd=tostring(args[1] or "help")
  local role=pkgdb.role()
  local sourceRole=role=="desktop" and "Desktop" or "Server"

  if cmd=="list" then
    local all=args[2]=="--all-reference"
    local rows=all and pkgdb.search("") or pkgdb.search("",{implemented_only=true})
    for _,p in ipairs(rows) do
      local status=p.implementation=="native" and "[installed,native]" or "[reference-only]"
      print(("%s/jammy %s %s %s"):format(
        p.name,p.version or "?",p.architecture or "lua",status))
    end
    if not all then
      print(("%d native package implementations. Use --all-reference for Ubuntu manifest entries."):format(#rows))
    end
    return 0

  elseif cmd=="show" then
    local name=args[2]
    if not name then print("E: No packages found");return 100 end
    local p,err=pkgdb.status(name)
    if not p then print("N: "..tostring(err));return 100 end
    print("Package: "..p.name)
    print("Version: "..tostring(p.version or "?"))
    print("Architecture: "..tostring(p.architecture or "lua"))
    print("Implementation: "..tostring(p.implementation))
    print("Status: "..(p.installed and "installed" or "not installed / reference only"))
    print("Source: "..tostring(p.source or ("Ubuntu 22.04.5 "..sourceRole.." manifest")))
    if #(p.commands or {})>0 then print("Commands: "..table.concat(p.commands,", ")) end
    return 0

  elseif cmd=="search" then
    local q=args[2] or ""
    local rows=pkgdb.search(q)
    for _,p in ipairs(rows) do
      local tag=p.implementation=="native" and "native" or "reference"
      print(("%-34s %-20s [%s]"):format(p.name,p.version or "?",tag))
    end
    return 0

  elseif cmd=="update" then
    local meta=pkgdb.load()
    print("Hit:1 CCLUA manager development jammy InRelease")
    print("Reading package lists... Done")
    print(("Native implementations: %d  Ubuntu reference entries: %d"):format(
      meta.implemented_count or 0,meta.reference_count or 0))
    print("All built-in CCLUA packages are current.")
    return 0

  elseif cmd=="upgrade" then
    print("Reading package lists... Done")
    print("Calculating upgrade... Done")
    print("CCLUA native software is upgraded through the manager image updater.")
    print("0 separately upgraded, 0 newly installed, 0 to remove.")
    return 0

  elseif cmd=="install" then
    local name=args[2]
    if not name then print("E: Missing package name");return 100 end
    local p=pkgdb.status(name)
    if not p then print("E: Unable to locate package "..name);return 100 end
    if p.installed then
      print(name.." is already provided by the current CCLUA image.")
      return 0
    end
    print("E: "..name.." is Ubuntu reference metadata only; no CCLUA implementation is available yet.")
    print("   Use cclua-appctl for deployable Lua applications.")
    return 100

  elseif cmd=="remove" then
    local name=args[2]
    if not name then print("E: Missing package name");return 100 end
    local p=pkgdb.status(name)
    if not p then print("E: Unable to locate package "..name);return 100 end
    if p.installed then
      print("E: built-in CCLUA image packages cannot be removed independently yet.")
      print("   Disable their service/app or deploy an alternate image instead.")
      return 100
    end
    print(name.." is not installed.")
    return 0
  end

  usage()
  return 0
end}
