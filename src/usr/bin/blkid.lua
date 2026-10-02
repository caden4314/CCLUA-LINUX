return {main=function(ctx,args)
 local idx=1
 for _,name in ipairs(peripheral.getNames())do
  if peripheral.hasType(name,"drive") then
   local d=peripheral.wrap(name)
   local id=d.getDiskID and d.getDiskID() or idx
   local label=d.getDiskLabel and d.getDiskLabel() or ""
   print(('/dev/ccdrive%d: LABEL="%s" UUID="CC-%s" TYPE="ccluafs"'):format(idx,label,tostring(id)))
   idx=idx+1
  end
 end
 return 0
end}
