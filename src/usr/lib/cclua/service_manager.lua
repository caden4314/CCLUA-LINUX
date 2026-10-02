local M={}
function M.new(kernel)
  local self={kernel=kernel,units={}}

  function self:register(unit)
    assert(unit and unit.name,"unit name required")
    unit.state=unit.state or "inactive"
    unit.enabled=unit.enabled==true
    self.units[unit.name]=unit
    return unit
  end

  function self:load_ubuntu_reference(path)
    path=path or "/usr/share/cclua/ubuntu-systemd-units.json"
    local host=path:gsub("^/","")
    if not fs.exists(host) then return 0 end
    local h=fs.open(host,"r")
    if not h then return 0 end
    local raw=h.readAll();h.close()
    local data=textutils.unserializeJSON(raw)
    if type(data)~="table" or type(data.units)~="table" then return 0 end
    local n=0
    for _,ref in ipairs(data.units) do
      if ref.name and not self.units[ref.name] then
        self.units[ref.name]={
          name=ref.name,
          description=ref.description or "Ubuntu 22.04.5 unit",
          state="inactive",
          enabled=false,
          reference=true,
          ubuntu=ref,
        }
        n=n+1
      end
    end
    return n
  end

  function self:get(name)
    if self.units[name] then return self.units[name] end
    if not tostring(name):find("%.") and self.units[name..".service"] then return self.units[name..".service"] end
    return nil
  end

  function self:list()
    local out={}
    for _,u in pairs(self.units) do out[#out+1]=u end
    table.sort(out,function(a,b)return a.name<b.name end)
    return out
  end

  function self:start(name)
    local u=self:get(name)
    if not u then return nil,"Unit "..tostring(name).." not found." end
    if u.state=="active" and u.pid then return true,u.pid end
    if type(u.exec)~="function" then return nil,"Unit has no executable." end

    local proc,err=kernel.process.create{
      ppid=1,name=u.name,uid=u.uid or 0,gid=u.gid or 0,cwd="/",
      capabilities=u.capabilities or kernel.capabilities.root(),
      argv={u.name}
    }
    if not proc then return nil,err end
    u.state="activating";u.pid=proc.pid

    kernel.scheduler:add(proc,function()
      u.state="active"
      kernel.log.write("info","service","Started "..u.name,nil,proc.pid)
      local ok,res=pcall(u.exec,{kernel=kernel,process=proc,unit=u})
      if not ok then
        u.state="failed";u.error=tostring(res)
        error(res,0)
      end
      u.state="inactive";u.pid=nil
      return tonumber(res) or 0
    end)
    return true,proc.pid
  end

  function self:stop(name)
    local u=self:get(name)
    if not u then return nil,"Unit "..tostring(name).." not found." end
    if not u.pid then u.state="inactive";return true end
    local p=kernel.process.get(u.pid)
    if p and p.state~="exited" and p.state~="killed" and p.state~="crashed" then
      kernel.process.exit(p,143,"killed")
      if os.queueEvent then os.queueEvent("cclua_process_exit",p.pid,p.exit_code,"killed") end
    end
    u.pid=nil;u.state="inactive"
    kernel.log.write("info","service","Stopped "..u.name)
    return true
  end

  function self:restart(name)
    local ok,err=self:stop(name);if not ok then return nil,err end
    return self:start(name)
  end

  function self:enable(name)
    local u=self:get(name);if not u then return nil,"Unit not found." end
    u.enabled=true;return true
  end

  function self:disable(name)
    local u=self:get(name);if not u then return nil,"Unit not found." end
    u.enabled=false;return true
  end

  function self:start_enabled()
    for _,u in ipairs(self:list()) do if u.enabled then self:start(u.name) end end
  end

  return self
end
return M
