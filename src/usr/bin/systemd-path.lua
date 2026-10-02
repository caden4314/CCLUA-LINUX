return {main=function(ctx,args)
 local map={["temporary"]="/tmp",["system-binaries"]="/usr/bin",["system-library-private"]="/usr/lib",["system-configuration-factory"]="/usr/share/factory/etc",["system-state-logs"]="/var/log",["user-home"]=(ctx.kernel.users.by_uid(ctx.process.uid) or {}).home or "/root"}
 if args[1] then local v=map[args[1]];if v then print(v);return 0 end;return 1 end
 for k,v in pairs(map)do print(("%-32s %s"):format(k..":",v))end
 return 0
end}
