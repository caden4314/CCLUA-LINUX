return function(args,io,ctx)
  local value=args[2]
  if not value then
    io.write("usage: ssh-authorize cclua-ssh-pub:<key> [label]\n")
    return 2
  end
  local payload=value:match("^cclua%-ssh%-pub:(.+)$")
  if not payload then io.write("\27[91minvalid public key format\27[0m\n");return 2 end
  local crypto=ctx.iso.require("system/lib/crypto/init.lua")
  local auth=ctx.iso.require("system/lib/ssh_auth.lua")
  local raw=crypto.encoding.fromBase64(payload)
  if not raw then io.write("\27[91minvalid public key encoding\27[0m\n");return 2 end
  local ok,public=pcall(textutils.unserialize,raw)
  if not ok or type(public)~="table" or not public.x or not public.y then
    io.write("\27[91minvalid public key\27[0m\n");return 2
  end
  local fp=auth.authorize(public,args[3] or "remote-user")
  io.write("\27[92mAuthorized "..fp.."\27[0m\n")
  return 0
end
