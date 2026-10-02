local c=dofile("/usr/lib/cclua/util_linux.lua")
return {main=function(ctx,args)return c.run("last",ctx,args)end}
