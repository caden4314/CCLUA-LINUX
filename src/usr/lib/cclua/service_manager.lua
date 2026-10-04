local M={}
function M.new(kernel)
  local self={kernel=kernel,units={}}

  function self:register(unit)
    assert(unit and unit.name,"unit name required")
    unit.state=unit.state or "inactive"
    unit.enabled=unit.enabled==true
    if type(unit.exec)=="function" then
      if unit.restart==nil then unit.restart="on-failure" end
      unit.restart_delay=tonumber(unit.restart_delay) or 0.75
      unit.restart_max_delay=tonumber(unit.restart_max_delay) or 8
      unit.restart_burst=tonumber(unit.restart_burst) or 5
      unit.restart_window=tonumber(unit.restart_window) or 60
      unit.restart_count=tonumber(unit.restart_count) or 0
      unit.total_restarts=tonumber(unit.total_restarts) or 0
    end
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
    if (u.state=="active" or u.state=="activating") and u.pid then return true,u.pid end
    if type(u.exec)~="function" then return nil,"Unit has no executable." end

    local proc,err=kernel.process.create{
      ppid=1,name=u.name,uid=u.uid or 0,gid=u.gid or 0,cwd="/",
      capabilities=u.capabilities or kernel.capabilities.root(),
      argv={u.name}
    }
    if not proc then return nil,err end
    u.state="activating";u.pid=proc.pid
    u.error=nil
    u.traceback=nil

    local function trace_message(value)
      local msg=tostring(value)
      if debug and debug.traceback then
        local ok,trace=pcall(debug.traceback,msg,3)
        if ok and trace then return tostring(trace) end
      end
      return msg
    end

    local function should_restart()
      return u.restart=="always" or u.restart=="on-failure"
    end

    kernel.scheduler:add(proc,function()
      local attempt=0
      local burstStart=nil

      while true do
        u.state="active"
        u.started_at=(os.epoch and os.epoch("utc")) or 0
        kernel.log.write("info","service",
          attempt==0 and ("Started "..u.name) or ("Restarted "..u.name),
          {attempt=attempt,total_restarts=u.total_restarts or 0},proc.pid)

        local ok,res=pcall(u.exec,{kernel=kernel,process=proc,unit=u})
        if ok then
          u.last_exit_code=tonumber(res) or 0
          u.last_exit_at=(os.epoch and os.epoch("utc")) or 0
          if u.restart=="always" then
            -- An "always" unit treats a clean return as a restart request but
            -- keeps ownership of the current supervisor PID.
            res="service exited normally"
          else
            u.state="inactive"
            u.pid=nil
            return tonumber(res) or 0
          end
        end

        local stamp=((os.epoch and os.epoch("utc")) or 0)/1000
        if not burstStart or stamp-burstStart>u.restart_window then
          burstStart=stamp
          attempt=0
        end
        attempt=attempt+1
        u.restart_count=attempt
        u.total_restarts=(u.total_restarts or 0)+1
        u.error=tostring(res)
        u.traceback=trace_message(res)
        u.last_failure_at=(os.epoch and os.epoch("utc")) or 0

        local exhausted=attempt>u.restart_burst
        if not should_restart() or exhausted then
          u.state="failed"
          kernel.log.write("critical","service",
            exhausted
              and ("Restart limit reached for "..u.name)
              or ("Failed "..u.name..": "..u.error),
            {
              unit=u.name,error=u.error,traceback=u.traceback,pid=proc.pid,
              restart_count=attempt,restart_burst=u.restart_burst,
              total_restarts=u.total_restarts
            },proc.pid)
          error(res,0)
        end

        local delay=math.min(
          u.restart_max_delay,
          u.restart_delay*(2^math.max(0,attempt-1))
        )
        u.state="activating"
        kernel.log.write("warning","service","Service failure; scheduling restart",{
          unit=u.name,error=u.error,traceback=u.traceback,
          restart_in=delay,restart_count=attempt,
          restart_burst=u.restart_burst
        },proc.pid)

        if kernel.scheduler and kernel.scheduler.sleep then
          kernel.scheduler.sleep(delay)
        else
          sleep(delay)
        end

        -- stop() marks the process killed. Do not resurrect an explicitly
        -- stopped service after the backoff timer.
        if proc.state=="killed" or u.pid~=proc.pid then
          u.state="inactive"
          return 143
        end
      end
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
