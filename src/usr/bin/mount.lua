return {main=function(ctx,args)
 if #args==0 then
  local mounts=ctx.kernel.vfs.mounts();local names={}for n in pairs(mounts)do names[#names+1]=n end;table.sort(names)
  for _,n in ipairs(names)do print(("cclua on %s type ccluafs (rw)"):format(n))end
  return 0
 end
 if ctx.process.uid~=0 then print("mount: only root can mount filesystems");return 32 end
 local source=args[1];local target=args[2]
 if not target then print("mount: usage: mount <peripheral-drive> <target>");return 1 end
 local drive=peripheral.wrap(source)
 if not drive or not peripheral.hasType(source,"drive") then print("mount: "..source..": not a drive peripheral");return 32 end
 local mp=drive.getMountPath and drive.getMountPath()
 if not mp then print("mount: "..source..": no media mounted");return 32 end
 local provider=dofile("/System/kernel/persistfs.lua").new("/"..mp)
 ctx.kernel.vfs.mount(target,provider)
 print(source.." mounted on "..target)
 return 0
end}
