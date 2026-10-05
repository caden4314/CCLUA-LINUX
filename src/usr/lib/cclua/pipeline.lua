local M={}

local function tokenize(line)
  local out,buf={},{}
  local quote=nil
  local escape=false
  local function flush()
    if #buf>0 then out[#out+1]=table.concat(buf);buf={} end
  end
  local i=1
  while i<=#line do
    local c=line:sub(i,i)
    if escape then
      buf[#buf+1]=c;escape=false
    elseif c=="\\" then
      escape=true
    elseif quote then
      if c==quote then quote=nil else buf[#buf+1]=c end
    elseif c=="'" or c=='"' then
      quote=c
    elseif c:match("%s") then
      flush()
    elseif c=="2" and line:sub(i+1,i+1)==">" and #buf==0 then
      flush()
      if line:sub(i+2,i+3)=="&1" then
        out[#out+1]="2>&1";i=i+3
      elseif line:sub(i+2,i+2)==">" then
        out[#out+1]="2>>";i=i+2
      else
        out[#out+1]="2>";i=i+1
      end
    elseif c=="|" or c=="<" or c==">" then
      flush()
      if c==">" and line:sub(i+1,i+1)==">" then
        out[#out+1]=">>";i=i+1
      else
        out[#out+1]=c
      end
    else
      buf[#buf+1]=c
    end
    i=i+1
  end
  if escape or quote then return nil,"unterminated quote or escape" end
  flush()
  return out
end

function M.parse(line)
  local tokens,err=tokenize(tostring(line or ""))
  if not tokens then return nil,err end
  local stages={{argv={}}}
  local current=stages[1]
  local i=1
  while i<=#tokens do
    local tok=tokens[i]
    if tok=="|" then
      if #current.argv==0 then return nil,"empty pipeline stage" end
      current={argv={}}
      stages[#stages+1]=current
      i=i+1
    elseif tok=="2>&1" then
      current.stderr_to_stdout=true
      i=i+1
    elseif tok=="<" or tok==">" or tok==">>" or tok=="2>" or tok=="2>>" then
      local target=tokens[i+1]
      if not target or target=="|" or target=="<" or target==">" or target==">>"
          or target=="2>" or target=="2>>" or target=="2>&1" then
        return nil,"redirection missing target"
      end
      if tok=="<" then current.stdin=target
      elseif tok=="2>" or tok=="2>>" then
        current.stderr=target;current.stderr_append=tok=="2>>"
      else
        current.stdout=target;current.append=tok==">>"
      end
      i=i+2
    else
      current.argv[#current.argv+1]=tok
      i=i+1
    end
  end
  if #current.argv==0 then return nil,"empty pipeline stage" end
  return stages
end

local function abspath(ctx,path)
  if path:sub(1,1)~="/" then
    path=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..path)
  end
  return ctx.kernel.vfs.normalize(path)
end

function M.run(ctx,line)
  local stages,err=M.parse(line)
  if not stages then
    print("sh: "..tostring(err))
    return 2
  end

  for _,stage in ipairs(stages) do
    local path=ctx.kernel.exec.resolve(stage.argv[1])
    if not path then print(stage.argv[1]..": command not found");return 127 end
    local mod,loadErr=ctx.kernel.exec.load(path)
    if not mod then print(stage.argv[1]..": "..tostring(loadErr));return 126 end
    stage._path=path
    stage._mod=mod
  end

  local pipes={}
  for i=1,#stages-1 do
    local r,w=ctx.kernel.streams.pipe()
    pipes[i]={reader=r,writer=w}
  end

  local children={}
  local pgid=ctx.process.process_group
  local parentTerminal=ctx.process.terminal or (term and term.current and term.current())
  local parentOut=ctx.process.stdout or ctx.kernel.streams.terminal_writer(parentTerminal)
  local parentErr=ctx.process.stderr or parentOut
  for i,stage in ipairs(stages) do
    local mod=stage._mod

    local stdin=ctx.process.stdin
    local stdout=parentOut
    local stderr=parentErr
    local owned={}
    if i>1 then stdin=pipes[i-1].reader end
    if i<#stages then stdout=pipes[i].writer end

    if stage.stdin then
      local s,e=ctx.kernel.streams.file_reader(ctx.kernel,abspath(ctx,stage.stdin))
      if not s then print("sh: "..stage.stdin..": "..tostring(e));return 1 end
      stdin=s;owned[#owned+1]=s
    end
    if stage.stdout then
      local s,e=ctx.kernel.streams.file_writer(ctx.kernel,abspath(ctx,stage.stdout),stage.append)
      if not s then print("sh: "..stage.stdout..": "..tostring(e));return 1 end
      if i<#stages then pipes[i].writer:close() end
      stdout=s;owned[#owned+1]=s
    elseif i<#stages then
      owned[#owned+1]=stdout
    end

    if stage.stderr_to_stdout then
      stderr=stdout
    elseif stage.stderr then
      local s,e=ctx.kernel.streams.file_writer(ctx.kernel,abspath(ctx,stage.stderr),stage.stderr_append)
      if not s then print("sh: "..stage.stderr..": "..tostring(e));return 1 end
      stderr=s;owned[#owned+1]=s
    end

    local terminal
    if stdout==parentOut and parentTerminal then
      terminal=parentTerminal
    else
      terminal=ctx.kernel.streams.terminal(stdout,parentTerminal)
    end

    local child,cerr=ctx.kernel.process.create{
      ppid=ctx.process.pid,name=stage.argv[1],uid=ctx.process.uid,gid=ctx.process.gid,
      groups=ctx.process.groups,cwd=ctx.process.cwd,environment=ctx.process.environment,
      capabilities=ctx.process.capabilities,argv=stage.argv,session_id=ctx.process.session_id,
      process_group=pgid,pty=ctx.process.pty,terminal=terminal,
      stdin=stdin,stdout=stdout,stderr=stderr,
      fd={[0]=stdin,[1]=stdout,[2]=stderr},owned_streams=owned,
    }
    if not child then print("sh: spawn failed: "..tostring(cerr));return 1 end
    if not pgid then
      pgid=child.pid
      child.process_group=pgid
    end
    children[#children+1]=child

    ctx.kernel.scheduler:add(child,function()
      local cctx={kernel=ctx.kernel,process=child,pty=child.pty}
      local args={}
      for n=2,#stage.argv do args[#args+1]=stage.argv[n] end
      local ok,res=pcall(mod.main,cctx,args)
      for _,stream in ipairs(child.owned_streams or {}) do
        if stream and stream.close then pcall(stream.close,stream) end
      end
      if not ok then error(res,0) end
      return tonumber(res) or 0
    end)
  end

  local remaining=#children
  while remaining>0 do
    local _,pid=coroutine.yield("wait_event","cclua_process_exit")
    for _,child in ipairs(children) do
      if child.pid==pid and not child._pipeline_reaped then
        child._pipeline_reaped=true
        remaining=remaining-1
        break
      end
    end
  end

  return children[#children].exit_code or 1
end

return M
