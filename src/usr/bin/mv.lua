local function basename(p)return p:match("([^/]+)/*$") or p end
return {main=function(ctx,args)
 if #args<2 then print("mv: missing file operand");return 1 end
 local src=args[#args-1];local dst=args[#args]
 if src:sub(1,1)~="/" then src=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..src) end
 if dst:sub(1,1)~="/" then dst=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..dst) end
 if ctx.kernel.vfs.isDir(dst) then dst=ctx.kernel.vfs.normalize(dst.."/"..basename(src)) end
 local ok,err=ctx.kernel.vfs.move(src,dst)
 if not ok then print("mv: cannot move '"..src.."': "..tostring(err));return 1 end
 return 0
end}
