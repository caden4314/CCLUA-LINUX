return {main=function(ctx,args)
 if ctx.process.uid~=0 then print("umount: only root can unmount filesystems");return 32 end
 if not args[1] then print("umount: missing target");return 1 end
 local ok,e=ctx.kernel.vfs.unmount(args[1])
 if not ok then print("umount: "..args[1]..": "..tostring(e));return 32 end
 return 0
end}
