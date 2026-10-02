local c=dofile("/usr/lib/cclua/procps.lua")
return {main=function(ctx,args)return c.run("pgrep",ctx,args)end}
