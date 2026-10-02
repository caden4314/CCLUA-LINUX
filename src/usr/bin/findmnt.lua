return {main=function(ctx,args)
 print("TARGET       SOURCE         FSTYPE      OPTIONS")
 local mounts=ctx.kernel.vfs.mounts()
 local names={}for n in pairs(mounts)do names[#names+1]=n end;table.sort(names)
 for _,n in ipairs(names)do
  local src=(n=="/" and "cclua-root") or (n=="/proc" and "proc") or (n=="/dev" and "devtmpfs") or (n=="/sys" and "sysfs") or "cclua"
  local typ=(n=="/proc" and "proc") or (n=="/dev" and "devtmpfs") or (n=="/sys" and "sysfs") or "ccluafs"
  print(("%-12s %-14s %-11s rw"):format(n,src,typ))
 end
 return 0
end}
