local M={}
function M.new(k)
 local p={}
 function p.exists(path)return path=="/" or path=="/class" or path=="/class/peripheral"end
 function p.isDir(path)return p.exists(path)end
 function p.list(path)
  if path=="/" then return {"class"}
  elseif path=="/class" then return {"peripheral"}
  elseif path=="/class/peripheral" then local o={}for n in pairs(k.device.devices)do o[#o+1]=n end;table.sort(o);return o end
  return {}
 end
 return p
end
return M
