local c=dofile("/usr/lib/cclua/procps.lua")
return {main=function(ctx,args)return c.run("vmstat",ctx,args)end}
