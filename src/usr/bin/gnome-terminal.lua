local exec=dofile("/usr/lib/cclua/exec.lua")
return {main=function(ctx,args)return exec.run(ctx,{"bash"},{cwd=ctx.process.cwd})end}
