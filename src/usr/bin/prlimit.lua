local c=dofile("/usr/lib/cclua/util_linux.lua")
return {main=function(ctx,args)return c.run("prlimit",ctx,args)end}
