local mod=dofile("/usr/bin/cclua-files.lua")
return {main=function(ctx,args)return mod.main(ctx,args)end}
