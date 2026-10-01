local Pty=ISO.require("system/kernel/pty.lua")
local M={}

local FINAL={exited=true,crashed=true,killed=true}

local function capSet(values)
  local out={}
  if type(values)=="table" then
    for k,v in pairs(values) do
      if type(k)=="number" then out[tostring(v)]=true
      elseif v then out[tostring(k)]=true end
    end
  end
  return out
end

local function capMatch(set,cap)
  if set["*"] or set[cap] then return true end
  for granted in pairs(set) do
    if granted:sub(-2)==".*" then
      local prefix=granted:sub(1,-3)
      if cap==prefix or cap:sub(1,#prefix+1)==prefix.."." then return true end
    end
  end
  return false
end

function M.new(ctx,scheduler)
  local self={ctx=ctx,scheduler=scheduler,processes={},sessions={},created=0,signals=0,denied=0}

  local function sync(pid)
    local rec=self.processes[tonumber(pid)]
    if not rec then return nil end
    local task=scheduler:get(pid)
    if task then
      rec.state=task.state
      rec.error=task.lastError
      rec.startedAt=task.startedAt
      rec.endedAt=task.endedAt
      rec.resumes=task.resumes
      rec.events=task.events
      if FINAL[task.state] and rec.pty and not rec.pty.closed then rec.pty:close() end
    end
    return rec
  end

  local function storageClass(path)
    path=ctx.vfs.normalize(path)
    if path=="/System" or path:sub(1,8)=="/System/" then return "fs.system" end
    if path=="/AppData" or path:sub(1,9)=="/AppData/" then return "fs.appdata" end
    if path=="/Temp" or path:sub(1,6)=="/Temp/" then return "fs.temp" end
    local home=ctx.config.user.home
    local alias="/home/"..ctx.config.user.name
    if path==home or path:sub(1,#home+1)==home.."/" or
       path==alias or path:sub(1,#alias+1)==alias.."/" or
       path=="/Users" or path:sub(1,7)=="/Users/" or path=="/home" then return "fs.user" end
    return "fs.virtual"
  end

  function self:has(pid,cap)
    local rec=self.processes[tonumber(pid)]
    return rec and capMatch(rec.capabilities,tostring(cap)) or false
  end

  function self:require(pid,cap)
    if self:has(pid,cap) then return true end
    self.denied=self.denied+1
    return nil,"capability denied: "..tostring(cap)
  end

  local function vfsProxy(pid)
    local proxy={}
    local function permit(path,mode)
      return self:require(pid,storageClass(path).."."..mode)
    end
    function proxy.normalize(path) return ctx.vfs.normalize(path) end
    function proxy.resolve(path)
      local ok,err=permit(path,"read");if not ok then return nil,err end
      return ctx.vfs.resolve(path)
    end
    function proxy.exists(path)
      local ok=permit(path,"read");if not ok then return false end
      return ctx.vfs.exists(path)
    end
    function proxy.isDir(path)
      local ok=permit(path,"read");if not ok then return false end
      return ctx.vfs.isDir(path)
    end
    function proxy.list(path)
      local ok,err=permit(path,"read");if not ok then return nil,err end
      return ctx.vfs.list(path)
    end
    function proxy.read(path)
      local ok,err=permit(path,"read");if not ok then return nil,err end
      return ctx.vfs.read(path)
    end
    function proxy.write(path,data,append)
      local ok,err=permit(path,"write");if not ok then return nil,err end
      return ctx.vfs.write(path,data,append)
    end
    function proxy.mkdir(path)
      local ok,err=permit(path,"write");if not ok then return nil,err end
      return ctx.vfs.mkdir(path)
    end
    function proxy.delete(path)
      local ok,err=permit(path,"write");if not ok then return nil,err end
      return ctx.vfs.delete(path)
    end
    function proxy.stat(path)
      local ok,err=permit(path,"read");if not ok then return nil,err end
      return ctx.vfs.stat(path)
    end
    return proxy
  end

  function self:context(pid)
    local rec=assert(self.processes[tonumber(pid)],"process not found")
    if rec.context then return rec.context end
    local view={
      process=rec,
      vfs=vfsProxy(pid),
      hasCapability=function(cap) return self:has(pid,cap) end,
      requireCapability=function(cap) return self:require(pid,cap) end,
      pty=rec.pty,
    }
    setmetatable(view,{__index=ctx})
    rec.context=view
    return view
  end

  function self:spawn(name,entry,opts)
    if type(entry)~="function" then return nil,"process entry must be a function" end
    opts=opts or {}
    local function runner()
      local task=scheduler:current()
      if not task then error("process has no scheduler task",0) end
      local rec={
        pid=task.pid,name=tostring(name or ("process-"..task.pid)),
        kind=tostring(opts.kind or "user"),user=tostring(opts.user or ctx.config.user.name),
        session=tostring(opts.session or "default"),cwd=opts.cwd or ctx.config.user.home,
        capabilities=capSet(opts.capabilities),state="running",
        protected=opts.protected==true,createdAt=os.clock(),
        pty=opts.pty and Pty.new(type(opts.pty)=="table" and opts.pty or {}) or nil,
      }
      self.processes[task.pid]=rec
      self.sessions[rec.session]=self.sessions[rec.session] or {}
      self.sessions[rec.session][task.pid]=true
      self.created=self.created+1
      return entry(self:context(task.pid))
    end
    local pid,err,failedPid=scheduler:spawn(name,runner,{
      protected=opts.protected,parent=opts.parent,args=opts.args,
    })
    pid=pid or failedPid
    if pid then sync(pid) end
    if not pid or err then return nil,err,pid end
    return pid,self.processes[pid]
  end

  function self:get(pid) return sync(pid) end

  function self:current()
    local task=scheduler:current()
    return task and sync(task.pid) or nil
  end

  function self:send(pid,event,...)
    local rec=sync(pid)
    if not rec then return nil,"process not found" end
    if FINAL[rec.state] then return nil,"process finished" end
    return scheduler:send(pid,event,...)
  end

  function self:signal(pid,signal,callerPid)
    local rec=sync(pid)
    if not rec then return nil,"process not found" end
    signal=tostring(signal or "TERM"):upper()
    if callerPid and tonumber(callerPid)~=tonumber(pid) then
      local caller=self.processes[tonumber(callerPid)]
      if not caller then return nil,"caller process not found" end
      if caller.user~=rec.user and not self:has(callerPid,"proc.signal.any") then
        self.denied=self.denied+1
        return nil,"capability denied: proc.signal.any"
      end
      if caller.user==rec.user and not self:has(callerPid,"proc.signal") and
         not self:has(callerPid,"proc.signal.any") then
        self.denied=self.denied+1
        return nil,"capability denied: proc.signal"
      end
    end
    if signal=="TERM" or signal=="KILL" or signal=="INT" then
      local ok,err=scheduler:kill(pid,signal,false)
      if not ok then return nil,err end
      self.signals=self.signals+1
      sync(pid)
      return true
    end
    return self:send(pid,"cclua_signal",signal)
  end

  function self:list(includeFinished)
    local out={}
    for pid in pairs(self.processes) do
      local rec=sync(pid)
      if rec and (includeFinished or not FINAL[rec.state]) then
        local caps={};for cap in pairs(rec.capabilities) do caps[#caps+1]=cap end;table.sort(caps)
        out[#out+1]={
          pid=rec.pid,name=rec.name,kind=rec.kind,user=rec.user,
          session=rec.session,state=rec.state,cwd=rec.cwd,
          protected=rec.protected,capabilities=caps,
          resumes=rec.resumes or 0,events=rec.events or 0,error=rec.error,
          pty=rec.pty and rec.pty:status() or nil,
        }
      end
    end
    table.sort(out,function(a,b)return a.pid<b.pid end)
    return out
  end

  function self:status()
    local s={active=0,exited=0,crashed=0,killed=0,created=self.created,signals=self.signals,denied=self.denied,sessions=0}
    for _ in pairs(self.sessions) do s.sessions=s.sessions+1 end
    for _,p in ipairs(self:list(true)) do
      s[p.state]=(s[p.state] or 0)+1
      if not FINAL[p.state] then s.active=s.active+1 end
    end
    return s
  end

  return self
end

return M

