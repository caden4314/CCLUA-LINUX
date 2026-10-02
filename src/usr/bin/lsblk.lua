return {main=function(ctx,args)
 print("NAME       MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS")
 print("cclua0       0:0    0 dynamic  0 disk /")
 local idx=1
 for _,name in ipairs(peripheral.getNames())do
  if peripheral.hasType(name,"drive") then
   local d=peripheral.wrap(name)
   local mp=d.getMountPath and d.getMountPath() or nil
   local label=d.getDiskLabel and d.getDiskLabel() or nil
   print(("ccdrive%-2d   1:%-2d   1 dynamic  0 disk %s"):format(idx,idx,mp and ("/"..mp) or ""))
   if label then print("  label: "..label)end
   idx=idx+1
  end
 end
 return 0
end}
