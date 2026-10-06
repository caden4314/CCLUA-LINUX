local pkgdb=dofile("/usr/lib/cclua/package_db.lua")

return {main=function(ctx,args)
  if args[1]=="-l" or args[1]=="--list" then
    print("Desired=Unknown/Install/Remove/Purge/Hold")
    print("| Status=Not/Inst/Conf-files/Unpacked/halF-conf/Half-inst/trig-aWait/Trig-pend")
    print("||/ Name                           Version                    Arch")
    for _,p in ipairs(pkgdb.implemented()) do
      print(("ii  %-30s %-26s %s"):format(
        p.name,p.version or "?",p.architecture or "lua"))
    end
    return 0
  elseif args[1]=="-s" or args[1]=="--status" then
    local name=args[2]
    if not name then print("dpkg-query: no package name supplied");return 2 end
    local p,err=pkgdb.status(name)
    if not p then print("dpkg-query: package '"..tostring(name).."' is not installed");return 1 end
    if not p.installed then
      print(("dpkg-query: package '%s' is Ubuntu reference metadata only"):format(name))
      return 1
    end
    print("Package: "..p.name)
    print("Status: install ok installed")
    print("Architecture: "..tostring(p.architecture or "lua"))
    print("Version: "..tostring(p.version or "?"))
    print("Description: CCLUA native implementation")
    if #(p.commands or {})>0 then print("Provides-Commands: "..table.concat(p.commands,", ")) end
    return 0
  elseif args[1]=="--version" then
    print("Debian 'dpkg' package management program version 1.21.1 (CCLUA compatibility)")
    return 0
  end
  print("dpkg: supported options: -l, --list, -s <package>, --status <package>, --version")
  return 0
end}
