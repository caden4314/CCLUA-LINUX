return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local net=dofile("/usr/lib/cclua/net.lua")
  local machine=config.machine()
  local protocol="cclua-manager-v1"
  local managerId=tonumber(machine.manager_computer_id) or 0
  local pollSeconds=tonumber(machine.update_poll_seconds) or 3
  local pollJitter=(os.getComputerID()%7)*0.11
  local autoApply=machine.auto_apply_updates~=false
  local stageSpreadSeconds=tonumber(machine.update_stage_spread_seconds) or 18
  local statusTimeout=tonumber(machine.update_status_timeout_seconds) or 5
  local manifestTimeout=tonumber(machine.update_manifest_timeout_seconds) or 10
  local transferTimeout=tonumber(machine.update_transfer_timeout_seconds) or 12
  local retryBaseSeconds=tonumber(machine.update_retry_base_seconds) or 4
  local ROOT="/var/lib/cclua/node-update"
  local STATE=ROOT.."/state.json"
  local INSTALLED_MANIFEST=ROOT.."/installed-manifest.json"
  local runtime={
    state="BOOTING",progress=0,total=0,currentAction=nil,currentFile=nil,
    targetCommit=nil,lastError=nil,lastResult=nil,delta={added=0,changed=0,removed=0,unchanged=0},
    downloadedBytes=0,startedAt=nil,
    stageTarget=nil,stageAt=nil,stageFailures=0,retryAt=nil
  }
  local lastManager=nil
  local consecutiveManagerFailures=0
  local managerFailureThreshold=tonumber(machine.manager_failure_threshold) or 3

  local function now_ms() return os.epoch and os.epoch("utc") or 0 end
  local function host(path) return tostring(path):gsub("^/","") end

  local function ensure(path)
    path=host(path)
    if path=="" or fs.exists(path) then return end
    local parent=fs.getDir(path)
    if parent~="" and not fs.exists(parent) then ensure(parent) end
    fs.makeDir(path)
  end

  local function read_all(path)
    path=host(path)
    if not fs.exists(path) then return nil end
    local h=fs.open(path,"r")
    if not h then return nil end
    local v=h.readAll();h.close();return v
  end

  local function write_all(path,data)
    path=host(path)
    ensure(fs.getDir(path))
    local h,err=fs.open(path,"w")
    if not h then return nil,err or "open failed" end
    h.write(data or "");h.close();return true
  end

  local function read_json(path,default)
    local raw=read_all(path)
    if not raw then return default end
    local ok,v=pcall(textutils.unserializeJSON,raw)
    return ok and type(v)=="table" and v or default
  end

  local function write_json(path,value)
    return write_all(path,textutils.serializeJSON(value))
  end

  local function read_text(path)
    local v=read_all(path)
    return v and v:gsub("%s+$","") or nil
  end

  local function local_commit()
    return read_text("/var/lib/cclua/installed-commit")
      or machine.image_commit or machine.build_commit or "unknown"
  end

  local function load_state()
    local s=read_json(STATE,{schema=1,activeSlot="A"})
    s.activeSlot=s.activeSlot=="B" and "B" or "A"
    return s
  end

  local function save_state(s)
    ensure(ROOT)
    return write_json(STATE,s)
  end

  local function slot_root(slot) return ROOT.."/"..slot end

  local function manifest_from(path)
    local m=read_json(path,nil)
    if type(m)=="table" and type(m.files)=="table" then return m end
    return nil
  end

  local function installed_manifest()
    return manifest_from(INSTALLED_MANIFEST)
  end

  local function progress_percent()
    if runtime.total<=0 then return runtime.state=="CURRENT" and 100 or 0 end
    return math.floor(math.min(1,runtime.progress/runtime.total)*100)
  end

  local function payload(extra)
    local p={
      schema=2,
      state=runtime.state,
      current_commit=local_commit(),
      available_commit=runtime.targetCommit or (lastManager and lastManager.commit) or nil,
      target_commit=runtime.targetCommit,
      manager_id=managerId,
      manager_commit=lastManager and lastManager.commit or nil,
      manager_ref=lastManager and lastManager.ref or nil,
      manager_state=lastManager and lastManager.managerState or nil,
      checked_at=os.epoch and os.epoch("utc") or 0,
      progress=runtime.progress,
      total=runtime.total,
      percent=progress_percent(),
      current_action=runtime.currentAction,
      current_file=runtime.currentFile,
      downloaded_bytes=runtime.downloadedBytes,
      delta=runtime.delta,
      last_error=runtime.lastError,
      last_result=runtime.lastResult,
      started_at=runtime.startedAt,
      auto_apply=autoApply,
    }
    for k,v in pairs(extra or {}) do p[k]=v end
    return p
  end

  local function write_state(state,extra)
    runtime.state=state
    if state~="FAILED" and state~="OFFLINE" then runtime.lastError=nil end
    local p=payload(extra)
    config.write_json("/var/lib/cclua/update-state.json",p)
    config.write_json("/var/log/cclua/update-health.json",p)
    pcall(rednet.send,managerId,{
      protocol=protocol,
      op="node_update_status",
      hostname=machine.hostname,
      role=machine.role,
      status={
        hostname=machine.hostname,
        role=machine.role,
        system_state=(state=="FAILED" or state=="OFFLINE") and "DEGRADED"
          or ((state=="CURRENT") and "HEALTHY" or "UPDATING"),
        current_commit=local_commit(),
        update=p,
      }
    },protocol)
  end

  local function open_modems()
    return net.open_management_modems()
  end

  local function node_status()
    local health=config.read_json("/var/lib/cclua/status.json",{})
    local update=config.read_json("/var/lib/cclua/update-state.json",{})
    return {
      hostname=machine.hostname,
      role=machine.role,
      system_state=health.state or "BOOTING",
      current_commit=local_commit(),
      update=update,
      processes=#ctx.kernel.process.all(),
      services=(function()
        local n=0
        for _,u in ipairs(ctx.kernel.services:list()) do if u.state=="active" then n=n+1 end end
        return n
      end)(),
      peripherals=(function()
        local n=0
        for _ in pairs(ctx.kernel.device.devices or {}) do n=n+1 end
        return n
      end)()
    }
  end

  local function rpc(msg,timeout)
    msg.protocol=protocol
    local ok=rednet.send(managerId,msg,protocol)
    if not ok then return nil,"manager send failed" end
    local timer=os.startTimer(timeout or 3)
    while true do
      local ev,a,b,c=coroutine.yield("wait_event")
      if ev=="rednet_message" and a==managerId and c==protocol and type(b)=="table" and b.protocol==protocol then
        if b.op==msg.op then
          if b.ok==false then return nil,b.error or "manager request failed" end
          return b
        end
        if b.op=="image_available" and type(b.status)=="table" then lastManager=b.status end
      elseif ev=="timer" and a==timer then
        return nil,"manager timeout"
      end
    end
  end

  local function request_status()
    local res,err=rpc({
      op="status",hostname=machine.hostname,role=machine.role,status=node_status()
    },statusTimeout)
    if not res then return nil,err end
    if type(res.status)=="table" then
      lastManager=res.status
      runtime.targetCommit=tostring(lastManager.commit or "unknown")
    end
    return lastManager
  end

  local function fetch_manifest()
    local res,err=rpc({op="manifest"},manifestTimeout)
    if not res then return nil,err end
    if type(res.manifest)~="table" or type(res.manifest.files)~="table" then
      return nil,"manager returned invalid manifest"
    end
    return res.manifest
  end

  local function safe_rel(path)
    if type(path)~="string" or path=="" then return nil end
    path=path:gsub("\\","/")
    if path:sub(1,1)=="/" then return nil end
    local out={}
    for seg in path:gmatch("[^/]+") do
      if seg=="" or seg=="." or seg==".." then return nil end
      out[#out+1]=seg
    end
    return #out>0 and table.concat(out,"/") or nil
  end

  local function fetch_file(rel,dest,expected)
    rel=safe_rel(rel)
    if not rel then return nil,"invalid path" end
    dest=host(dest)
    ensure(fs.getDir(dest))
    if fs.exists(dest) then fs.delete(dest) end

    local offset=0
    local total=tonumber(expected) or 0
    while true do
      local res,err=rpc({op="read_chunk",path=rel,offset=offset,size=12000},transferTimeout)
      if not res then return nil,err end
      if type(res.data)~="string" then return nil,"invalid file chunk" end
      local h,e=fs.open(dest,offset==0 and "w" or "a")
      if not h then return nil,e or "cannot write staged file" end
      h.write(res.data);h.close()
      offset=offset+#res.data
      runtime.downloadedBytes=runtime.downloadedBytes+#res.data
      runtime.currentAction="DOWNLOAD"
      runtime.currentFile=rel
      config.write_json("/var/lib/cclua/update-state.json",payload())
      if res.eof then break end
      if #res.data==0 then return nil,"zero-length non-final chunk" end
    end
    if total>0 and offset~=total then
      return nil,("size mismatch %s: got %d expected %d"):format(rel,offset,total)
    end
    return true
  end

  local function copy_tree(src,dst)
    src=host(src);dst=host(dst)
    if not fs.exists(src) then return true end
    if fs.exists(dst) then fs.delete(dst) end
    ensure(fs.getDir(dst))
    local ok,err=pcall(fs.copy,src,dst)
    return ok and true or nil,ok and nil or tostring(err)
  end

  local function seed_slot(slot,manifest)
    local root=slot_root(slot)
    if fs.exists(host(root)) then fs.delete(host(root)) end
    ensure(root)
    local mappings={
      {"System/kernel",root.."/kernel"},
      {"System/init",root.."/init"},
      {"usr",root.."/usr"},
      {"lib",root.."/lib"},
      {"etc",root.."/etc"},
    }
    for _,m in ipairs(mappings) do
      local ok,err=copy_tree(m[1],m[2])
      if not ok then return nil,err end
    end
    write_json(root.."/.manifest.json",manifest or {schema=1,commit=local_commit(),files={}})
    write_all(root.."/.commit",local_commit().."\n")
    return true
  end

  local function slot_usable(slot)
    local r=host(slot_root(slot))
    return fs.exists(fs.combine(r,"kernel/init.lua"))
      and fs.exists(fs.combine(r,"init/init.lua"))
      and fs.exists(fs.combine(r,"usr"))
      and fs.exists(fs.combine(r,".manifest.json"))
  end

  local function calculate_delta(old,new)
    old=old or {files={}};new=new or {files={}}
    local added,changed,removed,unchanged={},{},{},{}
    for rel,meta in pairs(new.files or {}) do
      local prior=old.files and old.files[rel] or nil
      if not prior then added[#added+1]=rel
      elseif prior.sha~=meta.sha then changed[#changed+1]=rel
      else unchanged[#unchanged+1]=rel end
    end
    for rel in pairs(old.files or {}) do
      if not (new.files or {})[rel] then removed[#removed+1]=rel end
    end
    table.sort(added);table.sort(changed);table.sort(removed);table.sort(unchanged)
    return added,changed,removed,unchanged
  end

  local function stage(targetStatus)
    local target=tostring(targetStatus.commit or "")
    if target=="" or target=="unknown" then return nil,"manager has no image commit" end
    runtime.targetCommit=target

    local current=local_commit()
    local targetManifest,err=fetch_manifest()
    if not targetManifest then return nil,err end

    if current==target then
      if not installed_manifest() then
        write_json(INSTALLED_MANIFEST,targetManifest)
      end
      runtime.progress=0;runtime.total=0
      runtime.delta={added=0,changed=0,removed=0,unchanged=(function() local n=0 for _ in pairs(targetManifest.files or {}) do n=n+1 end return n end)()}
      runtime.lastResult="current"
      write_state("CURRENT",{available_commit=target})
      return true,false
    end

    runtime.startedAt=os.epoch and os.epoch("utc") or 0
    runtime.downloadedBytes=0
    runtime.currentAction="PREPARE"
    runtime.currentFile="local A/B snapshot"
    write_state("STAGING")

    local state=load_state()
    local oldManifest=installed_manifest() or {schema=1,commit=current,files={}}

    if not slot_usable(state.activeSlot) then
      local ok,seedErr=seed_slot(state.activeSlot,oldManifest)
      if not ok then return nil,"seed active slot: "..tostring(seedErr) end
    end

    local inactive=state.activeSlot=="A" and "B" or "A"
    local activeRoot=slot_root(state.activeSlot)
    local stageRoot=slot_root(inactive)
    if fs.exists(host(stageRoot)) then fs.delete(host(stageRoot)) end
    local copied,copyErr=pcall(fs.copy,host(activeRoot),host(stageRoot))
    if not copied then return nil,"copy stage: "..tostring(copyErr) end

    local added,changed,removed,unchanged=calculate_delta(oldManifest,targetManifest)
    runtime.delta={added=#added,changed=#changed,removed=#removed,unchanged=#unchanged}
    runtime.total=#added+#changed+#removed
    runtime.progress=0
    write_state("STAGING")

    for _,rel in ipairs(removed) do
      runtime.currentAction="REMOVE";runtime.currentFile=rel
      local p=host(stageRoot.."/"..rel)
      if fs.exists(p) then fs.delete(p) end
      runtime.progress=runtime.progress+1
      write_state("STAGING")
    end

    local function apply(list,action)
      for _,rel in ipairs(list) do
        runtime.currentAction=action;runtime.currentFile=rel
        write_state("DOWNLOADING")
        local meta=targetManifest.files[rel] or {}
        local ok,fetchErr=fetch_file(rel,stageRoot.."/"..rel,meta.size)
        if not ok then return nil,fetchErr end
        runtime.progress=runtime.progress+1
        write_state("DOWNLOADING")
      end
      return true
    end

    local ok,applyErr=apply(changed,"CHANGE")
    if not ok then return nil,applyErr end
    ok,applyErr=apply(added,"ADD")
    if not ok then return nil,applyErr end

    runtime.currentAction="VERIFY";runtime.currentFile="manifest"
    write_state("VERIFYING")
    write_json(stageRoot.."/.manifest.json",targetManifest)
    write_all(stageRoot.."/.commit",target.."\n")

    state.pendingSlot=inactive
    state.pendingCommit=target
    state.previousSlot=state.activeSlot
    state.requestedAt=os.epoch and os.epoch("utc") or 0
    state.lastDelta=runtime.delta
    save_state(state)

    runtime.progress=runtime.total
    runtime.currentAction=nil;runtime.currentFile=nil
    runtime.lastResult="staged"
    write_state("READY",{pending_slot=inactive,pending_commit=target})

    if autoApply then
      runtime.currentAction="REBOOT"
      runtime.currentFile="activating staged image"
      write_state("ACTIVATING",{pending_slot=inactive,pending_commit=target})
      ctx.kernel.log.write("info","update-agent","automatic node update ready; rebooting",{
        current=current,target=target,slot=inactive,delta=runtime.delta,bytes=runtime.downloadedBytes
      },ctx.process.pid)
      local wake=(os.epoch and os.epoch("utc") or 0)+500
      coroutine.yield("sleep",wake)
      os.reboot()
    end
    return true,true
  end

  local function consider(status,reason)
    if type(status)~="table" then return end
    lastManager=status
    runtime.targetCommit=tostring(status.commit or "unknown")
    local current=local_commit()
    local now=now_ms()

    if current==runtime.targetCommit then
      if not installed_manifest() then
        local m=fetch_manifest()
        if m then write_json(INSTALLED_MANIFEST,m) end
      end
      runtime.stageTarget=nil
      runtime.stageAt=nil
      runtime.retryAt=nil
      runtime.stageFailures=0
      runtime.lastResult=reason=="announce" and "confirmed by manager" or runtime.lastResult
      write_state("CURRENT",{available_commit=runtime.targetCommit})
      return
    end

    if runtime.state=="DOWNLOADING" or runtime.state=="STAGING" or runtime.state=="VERIFYING" or runtime.state=="ACTIVATING" then
      return
    end

    -- Deterministically spread a fleet update across a short window. This
    -- prevents every computer from asking the manager for the same manifest
    -- and file chunks at once after an image announcement or world restart.
    if runtime.stageTarget~=runtime.targetCommit then
      runtime.stageTarget=runtime.targetCommit
      runtime.stageFailures=0
      runtime.retryAt=nil
      local fraction=((os.getComputerID()*37)%101)/100
      local delay=stageSpreadSeconds*fraction
      runtime.stageAt=now+math.floor(delay*1000)
      runtime.lastResult="scheduled"
      write_state("AVAILABLE",{
        stage_not_before=runtime.stageAt,
        stage_delay_seconds=delay,
        available_commit=runtime.targetCommit
      })
      return
    end

    if runtime.retryAt and now<runtime.retryAt then
      write_state("AVAILABLE",{
        retry_at=runtime.retryAt,
        retry_in_seconds=math.max(0,(runtime.retryAt-now)/1000),
        retry_count=runtime.stageFailures,
        available_commit=runtime.targetCommit
      })
      return
    end

    if runtime.stageAt and now<runtime.stageAt then
      write_state("AVAILABLE",{
        stage_not_before=runtime.stageAt,
        stage_delay_seconds=math.max(0,(runtime.stageAt-now)/1000),
        available_commit=runtime.targetCommit
      })
      return
    end

    local ok,err=stage(status)
    if ok then
      runtime.stageFailures=0
      runtime.retryAt=nil
      return
    end

    runtime.stageFailures=runtime.stageFailures+1
    runtime.lastError=tostring(err)
    local backoff=math.min(30,retryBaseSeconds*(2^(math.min(runtime.stageFailures-1,3))))
    runtime.retryAt=now_ms()+math.floor(backoff*1000)

    if runtime.stageFailures>=5 then
      runtime.lastResult="failed"
      write_state("FAILED",{
        error=runtime.lastError,
        retry_count=runtime.stageFailures,
        retry_at=runtime.retryAt
      })
      ctx.kernel.log.write("error","update-agent","automatic update repeatedly failed",{
        error=runtime.lastError,target=runtime.targetCommit,retries=runtime.stageFailures
      },ctx.process.pid)
    else
      runtime.lastResult="retry_wait"
      write_state("AVAILABLE",{
        warning=runtime.lastError,
        retry_count=runtime.stageFailures,
        retry_at=runtime.retryAt,
        retry_in_seconds=backoff,
        available_commit=runtime.targetCommit
      })
      ctx.kernel.log.write("warning","update-agent","automatic update transfer retry scheduled",{
        error=runtime.lastError,target=runtime.targetCommit,retry=runtime.stageFailures,
        backoff_seconds=backoff
      },ctx.process.pid)
    end
  end

  local function manager_success(status,reason)
    consecutiveManagerFailures=0
    runtime.lastError=nil
    consider(status,reason)
  end

  local function manager_failure(err)
    consecutiveManagerFailures=consecutiveManagerFailures+1
    runtime.lastError=tostring(err or "manager unavailable")

    if consecutiveManagerFailures>=managerFailureThreshold then
      write_state("OFFLINE",{
        error=runtime.lastError,
        manager_failures=consecutiveManagerFailures,
        manager_failure_threshold=managerFailureThreshold
      })
    else
      local current=local_commit()
      local previous=config.read_json("/var/lib/cclua/update-state.json",{})
      local keep=(previous.state=="CURRENT" or (lastManager and current==tostring(lastManager.commit or "")))
        and "CURRENT" or "CHECKING"
      write_state(keep,{
        warning=runtime.lastError,
        manager_failures=consecutiveManagerFailures,
        manager_failure_threshold=managerFailureThreshold
      })
    end
  end

  local opened=open_modems()
  ctx.unit.details={
    protocol=protocol,manager_id=managerId,modems=opened,poll_seconds=pollSeconds,
    auto_apply=autoApply,manager_failure_threshold=managerFailureThreshold,
    stage_spread_seconds=stageSpreadSeconds,transfer_timeout_seconds=transferTimeout
  }
  ctx.kernel.log.write("info","update-agent","automatic manager update agent online",ctx.unit.details,ctx.process.pid)

  ensure(ROOT)
  write_state("CHECKING")
  local mgr,err=request_status()
  if mgr then manager_success(mgr,"startup")
  else manager_failure(err) end

  local poll=os.startTimer(pollSeconds+pollJitter)

  while true do
    local ev,a,b,c=coroutine.yield("wait_event")
    if ev=="timer" and a==poll then
      local mgr,pollErr=request_status()
      if mgr then manager_success(mgr,"poll")
      else manager_failure(pollErr) end
      poll=os.startTimer(pollSeconds+pollJitter)

    elseif ev=="rednet_message" and c==protocol and a==managerId and type(b)=="table" and b.protocol==protocol then
      if b.op=="image_available" and type(b.status)=="table" then
        manager_success(b.status,"announce")
      end

    elseif ev=="peripheral" or ev=="peripheral_detach" then
      opened=open_modems()
      ctx.unit.details.modems=opened
    end
  end
end
