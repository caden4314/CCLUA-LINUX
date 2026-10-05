local stdio=dofile("/usr/lib/cclua/stdio.lua")

local function source(ctx,file)
 if not file or file=="-" then return stdio.read_all(ctx),nil end
 if file:sub(1,1)~="/" then file=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..file) end
 local h,e=ctx.kernel.vfs.open(file,"r")
 if not h then return nil,e end
 local data=h.readAll and h.readAll() or ""
 if h.close then h.close() end
 return data,nil,file
end

return {main=function(ctx,args)
 local file=args[#args]
 local data,e,label=source(ctx,file)
 if data==nil then stdio.errorln(ctx,"wc: "..tostring(e));return 1 end
 local lines=0
 for _ in data:gmatch("\n") do lines=lines+1 end
 local words=0
 for _ in data:gmatch("%S+") do words=words+1 end
 local suffix=label and (" "..label) or ""
 print(("%d %d %d%s"):format(lines,words,#data,suffix))
 return 0
end}
