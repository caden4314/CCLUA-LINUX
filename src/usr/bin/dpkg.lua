local pkgdb=dofile("/usr/lib/cclua/package_db.lua")

return {main=function(ctx,args)
  local meta=pkgdb.load()
  if args[1]=="-l" or args[1]=="--list" then
    print("Desired=Unknown/Install/Remove/Purge/Hold")
    print("| Status=Not/Inst/Conf-files/Unpacked/halF-conf/Half-inst/trig-aWait/Trig-pend")
    print("||/ Name                           Version")
    for _,p in ipairs(meta.packages or {}) do
      print(("ii  %-30s %s"):format(p.name,p.version or "?"))
    end
    return 0
  elseif args[1]=="--version" then
    print("Debian 'dpkg' package management program version 1.21.1 (CCLUA compatibility)")
    return 0
  end
  print("dpkg: supported options: -l, --list, --version")
  return 0
end}
