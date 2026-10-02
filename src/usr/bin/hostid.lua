local c=dofile("/usr/lib/cclua/coreutils.lua")
return {main=function(ctx,args)return c.run("hostid",ctx,args)end}
