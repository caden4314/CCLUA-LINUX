local M={devices={}}
function M.scan()
 M.devices={}
 if not peripheral then return M.devices end
 for _,n in ipairs(peripheral.getNames())do M.devices[n]={name=n,types={peripheral.getType(n)},present=true}end
 return M.devices
end
function M.get(n)return M.devices[n]end
return M
