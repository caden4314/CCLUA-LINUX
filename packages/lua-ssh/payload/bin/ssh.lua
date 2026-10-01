return function(args,io,ctx)
  local dst=args[2]
  if not dst then
    io.write("usage: ssh <ccluanet-address> [user]\n")
    return 2
  end
  local svc=ctx.services and ctx.services:get("sshclientd")
  if not svc then
    io.write("\27[91mssh: client service unavailable\27[0m\n")
    return 1
  end
  local id,err=svc:connect(dst,args[3] or ctx.config.user.name)
  if not id then
    io.write("\27[91mssh: "..tostring(err).."\27[0m\n")
    return 1
  end
  return {remoteSession=id}
end
