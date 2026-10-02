local M={}
function M.new(k)
 local p={}
 function p.exists(path)
  if path=="/" or path=="/null" or path=="/zero" or path=="/random" or path=="/console" or path=="/tty" then return true end
  return k.device.get(path:sub(2))~=nil
 end
 function p.isDir(path)return path=="/"end
 function p.list(path)
  local o={"null","zero","random","console","tty"}
  for n in pairs(k.device.devices)do o[#o+1]=n end
  table.sort(o);return o
 end
 function p.open(path,mode)
  if path=="/null" then return {write=function()return true end,read=function()return nil end,close=function()end} end
  if path=="/zero" then return {read=function(n)return string.rep("\0",n or 1)end,close=function()end} end
  return nil,"ENODEV"
 end
 return p
end
return M
