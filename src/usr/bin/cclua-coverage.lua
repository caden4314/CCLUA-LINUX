return {main=function(ctx,args)
 local h=fs.open("usr/share/cclua/compatibility.json","r")
 if not h then print("coverage database unavailable");return 1 end
 local d=textutils.unserializeJSON(h.readAll());h.close()
 if not d then return 1 end
 local pct=(d.total_commands>0) and (d.implemented_count/d.total_commands*100) or 0
 print("CCLUA Ubuntu Server compatibility")
 print("Ubuntu reference: "..tostring(d.ubuntu_reference))
 print(("Commands implemented: %d / %d (%.1f%%)"):format(d.implemented_count,d.total_commands,pct))
 print("Commands remaining:   "..tostring(d.missing_count))
 if args[1]=="missing" then
  for _,n in ipairs(d.missing or {})do print(n)end
 elseif args[1]=="implemented" then
  for _,n in ipairs(d.implemented or {})do print(n)end
 end
 return 0
end}
