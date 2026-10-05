local M={}

local function copy_args(argv,start)
  local out={}
  for i=start or 1,#(argv or {}) do out[#out+1]=argv[i] end
  return out
end

local function terminal_state(p)
  if not p then return "missing" end
  if p.state=="exited" or p.state=="killed" or p.state=="crashed" then return "done" end
  if p.state=="stopped" then return "stopped" end
  return "running"
end

function M.new(ctx,opts)
  opts=opts or {}
  local m={
    ctx=ctx,jobs={},next_id=1,
    cols=opts.cols or 80,rows=opts.rows or 24,
    notify=opts.notify,
  }

  local function find_job(ref)
    if type(ref)=="table" then return ref end
    local n=tonumber(tostring(ref or ""):gsub("^%%",""))
    if not n then return nil end
    for _,job in ipairs(m.jobs) do
      if job.id==n or job.pid==n then return job end
    end
  end
  function m:resize(cols,rows)
    self.cols=math.max(1,tonumber(cols) or self.cols)
    self.rows=math.max(1,tonumber(rows) or self.rows)
    for _,job in ipairs(self.jobs) do
      if job.pty and not job.done then
        job.pty:resize(self.cols,self.rows)
        self.ctx.kernel.scheduler:send_group(job.pgid,{"term_resize"})
      end
    end
  end

  function m:refresh()
    local now=os.epoch and os.epoch("utc") or 0
    for _,job in ipairs(self.jobs) do
      local p=self.ctx.kernel.process.get(job.pid)
      if p and not self.ctx.kernel.process.is_terminal(p)
          and job.deadline and now>=job.deadline and not job.timeout_fired then
        job.timeout_fired=true
        job.timed_out=true
        self.ctx.kernel.syscalls.kill_group(self.ctx.process,job.pgid,"TERM")
      end
      job.state=terminal_state(p)
      job.done=job.state=="done"
      if p then
        job.exit_code=p.exit_code
        job.signal=p.signal
        job.error=p.error
      end
    end
    return self.jobs
  end

  function m:get(ref)
    self:refresh()
    return find_job(ref)
  end

  function m:foreground()
    self:refresh()
    for _,job in ipairs(self.jobs) do
      if job.foreground and not job.done and job.state~="stopped" then return job end
    end
  end
  function m:list(include_done)
    self:refresh()
    local out={}
    for _,job in ipairs(self.jobs) do
      if include_done or not job.done then out[#out+1]=job end
    end
    return out
  end

  function m:spawn(argv,spawnOpts)
    spawnOpts=spawnOpts or {}
    if type(argv)~="table" or not argv[1] then return nil,"EINVAL" end

    local path=self.ctx.kernel.exec.resolve(argv[1])
    if not path then return nil,"command not found",127 end
    local mod,err=self.ctx.kernel.exec.load(path)
    if not mod then return nil,tostring(err),126 end

    local jobId=self.next_id
    self.next_id=self.next_id+1
    local pty=self.ctx.kernel.pty.new(self.cols,self.rows,{
      id="job-"..jobId,
      notify=function()
        if self.notify then pcall(self.notify,jobId) end
      end,
    })
    local parent=self.ctx.process
    local child,cerr=self.ctx.kernel.process.create{
      ppid=parent.pid,name=argv[1],uid=spawnOpts.uid or parent.uid,
      gid=spawnOpts.gid or parent.gid,groups=spawnOpts.groups or parent.groups,
      cwd=spawnOpts.cwd or parent.cwd,
      environment=spawnOpts.environment or parent.environment,
      capabilities=spawnOpts.capabilities or parent.capabilities,
      argv=argv,session_id=spawnOpts.session_id or parent.session_id,
      pty=pty,job_id=jobId,background=spawnOpts.background==true,
    }
    if not child then return nil,cerr,1 end

    local job={
      id=jobId,pid=child.pid,pgid=child.process_group,argv=argv,
      command=table.concat(argv," "),pty=pty,
      foreground=spawnOpts.background~=true,
      background=spawnOpts.background==true,
      state="running",done=false,announced=false,
      started_at=os.epoch and os.epoch("utc") or 0,
      timeout_ms=tonumber(spawnOpts.timeout_ms),
    }
    if job.timeout_ms and job.timeout_ms>0 then
      job.deadline=job.started_at+job.timeout_ms
    end
    pty.foreground_pgid=job.foreground and job.pgid or nil
    self.jobs[#self.jobs+1]=job

    self.ctx.kernel.scheduler:add(child,function()
      local cctx={kernel=self.ctx.kernel,process=child,job=job,pty=pty}
      local args=copy_args(argv,2)
      local ok,res=pcall(mod.main,cctx,args)
      if not ok then error(res,0) end
      return tonumber(res) or 0
    end)
    return job
  end

  function m:send(job,ev)
    job=find_job(job)
    if not job or job.done then return nil,"ESRCH" end
    return self.ctx.kernel.scheduler:send_group(job.pgid,ev)
  end

  function m:signal(job,sig)
    job=find_job(job)
    if not job or job.done then return nil,"ESRCH" end
    local normalized=tostring(sig or "TERM"):upper():gsub("^SIG","")
    if normalized=="INT" or normalized=="TERM" or normalized=="KILL" or normalized=="HUP" then
      if job.pty and job.pty.use_alt then job.pty:set_alternate_screen(false) end
    end
    local ok,err=self.ctx.kernel.syscalls.kill_group(self.ctx.process,job.pgid,sig)
    self:refresh()
    return ok,err
  end

  function m:cancel(job,sig)
    job=find_job(job)
    if not job or job.done then return nil,"ESRCH" end
    job.cancelled=true
    return self:signal(job,sig or "TERM")
  end

  function m:stop(job)
    job=find_job(job)
    if not job then return nil,"ESRCH" end
    local ok,err=self:signal(job,"STOP")
    if ok then
      job.foreground=false;job.background=true
      job.pty.foreground_pgid=nil
    end
    return ok,err
  end
  function m:background_job(ref)
    local job=find_job(ref)
    if not job then return nil,"ESRCH" end
    if job.done then return nil,"ECHILD" end
    if job.state=="stopped" then
      local ok,err=self:signal(job,"CONT")
      if not ok then return nil,err end
    end
    job.foreground=false;job.background=true
    job.pty.foreground_pgid=nil
    return job
  end

  function m:foreground_job(ref)
    local job=find_job(ref)
    if not job then
      for i=#self.jobs,1,-1 do
        if not self.jobs[i].done then job=self.jobs[i];break end
      end
    end
    if not job then return nil,"ECHILD" end
    if job.done then return nil,"ECHILD" end
    for _,other in ipairs(self.jobs) do other.foreground=false end
    if job.state=="stopped" then
      local ok,err=self:signal(job,"CONT")
      if not ok then return nil,err end
    end
    job.foreground=true;job.background=false
    job.pty.foreground_pgid=job.pgid
    return job
  end

  return m
end

return M
