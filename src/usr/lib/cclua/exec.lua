local M={}

function M.run(ctx,argv,opts)
  opts=opts or {}
  if type(argv)~="table" or not argv[1] then return 0 end

  local path=ctx.kernel.exec.resolve(argv[1])
  if not path then
    print(argv[1]..": command not found")
    return 127
  end

  local mod,err=ctx.kernel.exec.load(path)
  if not mod then
    print(argv[1]..": "..tostring(err))
    return 126
  end

  local uid=opts.uid
  if uid==nil then uid=ctx.process.uid end
  local gid=opts.gid
  if gid==nil then gid=ctx.process.gid end

  local child,cerr=ctx.kernel.process.create{
    ppid=ctx.process.pid,
    name=argv[1],
    uid=uid,
    gid=gid,
    groups=opts.groups or ctx.process.groups,
    cwd=opts.cwd or ctx.process.cwd,
    environment=opts.environment or ctx.process.environment,
    capabilities=opts.capabilities or (uid==0 and ctx.kernel.capabilities.root() or ctx.process.capabilities),
    argv=argv,
    session_id=opts.session_id or ctx.process.session_id,
    process_group=opts.process_group or ctx.process.process_group,
    pty=opts.pty or ctx.process.pty,
    terminal=opts.terminal or ctx.process.terminal,
    stdin=opts.stdin or ctx.process.stdin,
    stdout=opts.stdout or ctx.process.stdout,
    stderr=opts.stderr or ctx.process.stderr
  }
  if not child then
    print("exec: spawn failed: "..tostring(cerr))
    return 1
  end

  ctx.kernel.scheduler:add(child,function()
    local cctx={kernel=ctx.kernel,process=child,pty=child.pty}
    local args={}
    for i=2,#argv do args[#args+1]=argv[i] end
    local ok,res=pcall(mod.main,cctx,args)
    if not ok then error(res,0) end
    return tonumber(res) or 0
  end)

  while child.state~="exited" and child.state~="killed" and child.state~="crashed" do
    local ev,pid=coroutine.yield("wait_event","cclua_process_exit")
    if ev=="cclua_process_exit" and pid==child.pid then break end
  end
  return child.exit_code or 1
end

return M
