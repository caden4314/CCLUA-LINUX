local c=dofile("/usr/lib/cclua/coreutils.lua")
return {main=function(ctx,args)return c.run("unlink",ctx,args)end}
