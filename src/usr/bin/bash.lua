local shell=dofile("/usr/lib/cclua/shell.lua")
return {main=function(ctx,args)return shell.run(ctx,args)end}
