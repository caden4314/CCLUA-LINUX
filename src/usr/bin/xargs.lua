local exec=dofile("/usr/lib/cclua/exec.lua")
return {main=function(ctx,args)
 local cmd={}
 for _,a in ipairs(args)do cmd[#cmd+1]=a end
 if #cmd==0 then cmd={"echo"} end
 local input=read() or ""
 for token in input:gmatch("%S+")do cmd[#cmd+1]=token end
 return exec.run(ctx,cmd)
end}
