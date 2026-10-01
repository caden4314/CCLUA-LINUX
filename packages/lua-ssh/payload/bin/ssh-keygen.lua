return function(args,io,ctx)
  local auth=ctx.iso.require("system/lib/ssh_auth.lua")
  local crypto=ctx.iso.require("system/lib/crypto/init.lua")
  local key=auth.userKey()
  local encoded=crypto.encoding.toBase64(textutils.serialize(key.public,{compact=true}))
  io.write("Public key fingerprint: "..auth.fingerprint(key.public).."\n")
  io.write("cclua-ssh-pub:"..encoded.."\n")
  return 0
end
