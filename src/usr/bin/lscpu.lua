local c=dofile("/usr/lib/cclua/util_linux.lua")
return {main=function(ctx,args)return c.run("lscpu",ctx,args)end}
