local M={}
M.known={["fs.read"]=true,["fs.write"]=true,["fs.mount"]=true,["proc.spawn"]=true,["proc.signal"]=true,["proc.inspect"]=true,["user.admin"]=true,["service.control"]=true,["net.bind"]=true,["net.admin"]=true,["device.access"]=true,["system.reboot"]=true,["system.update"]=true,["kernel.inspect"]=true}
function M.root() local c={} for n in pairs(M.known) do c[n]=true end return c end
function M.has(p,c) return p and (p.uid==0 or (p.capabilities and p.capabilities[c]==true)) or false end
function M.require(p,c) if M.has(p,c) then return true end return nil,"EPERM","capability required: "..tostring(c) end
return M
