return {main=function(ctx,args)
 local a=false;local kernel=false;local node=false;local release=false;local machine=false
 for _,v in ipairs(args)do if v=="-a" then a=true elseif v=="-s" then kernel=true elseif v=="-n" then node=true elseif v=="-r" then release=true elseif v=="-m" then machine=true end end
 if #args==0 then kernel=true end
 local parts={}
 if a or kernel then parts[#parts+1]="Linux" end
 if a or node then
  local h=fs.open("etc/hostname","r");parts[#parts+1]=(h and h.readLine()) or "cclua-server";if h then h.close()end
 end
 if a or release then parts[#parts+1]="5.15.0-cclua" end
 if a then parts[#parts+1]="#1 CCLUA Ubuntu 22.04.5" end
 if a or machine then parts[#parts+1]="cclua" end
 print(table.concat(parts," "))
 return 0
end}
