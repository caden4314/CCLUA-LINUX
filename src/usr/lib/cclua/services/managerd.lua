return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local machine=config.machine()

  local CFG={
    owner=machine.github_owner or "caden4314",
    repo=machine.github_repo or "CCLUA-LINUX",
    ref=machine.github_ref or machine.channel_ref or "main",
    root="/var/lib/cclua/github",
    protocol="cclua-manager-v1",
    fleetProtocol="cclua-fleet-v1",
    pollSeconds=math.max(10,tonumber(machine.github_poll_seconds) or 10),
    -- Change notifications are sent immediately. This is only the idle
    -- heartbeat/recovery broadcast, so keep it deliberately low-frequency.
    announceSeconds=math.max(15,tonumber(machine.update_announce_seconds) or 20),
  }

  local runtime={
    state="BOOTING",
    progress=0,total=0,
    currentAction=nil,currentFile=nil,
    lastError=nil,lastCheck=nil,
    delta={added=0,changed=0,removed=0,unchanged=0},
    downloadedBytes=0,
    nodes={},
    peersDirty=false,
    pendingRebootCommit=nil,
    rebootEarliest=nil,
    rebootDeadline=nil,
  }

  local function join(a,b)
    if a:sub(-1)=="/" then return a..b end
    return a.."/"..b
  end

  local function ensureDir(path)
    if path=="" or fs.exists(path) then return end
    local parent=fs.getDir(path)
    if parent~="" and not fs.exists(parent) then ensureDir(parent) end
    fs.makeDir(path)
  end

  local function writeAll(path,data)
    path=tostring(path):gsub("^/","")
    ensureDir(fs.getDir(path))
    local h,err=fs.open(path,"w")
    if not h then return nil,err or "open failed" end
    h.write(data)
    h.close()
    return true
  end

  local function readAll(path)
    path=tostring(path):gsub("^/","")
    if not fs.exists(path) then return nil end
    local h=fs.open(path,"r")
    if not h then return nil end
    local data=h.readAll()
    h.close()
    return data
  end

  local function readText(path)
    local v=readAll(path)
    return v and v:gsub("%s+$","") or nil
  end

  local function loadState()
    local raw=readAll(join(CFG.root,"state.json"))
    if not raw then return {activeSlot="A"} end
    local ok,state=pcall(textutils.unserializeJSON,raw)
    if not ok or type(state)~="table" then return {activeSlot="A"} end
    state.activeSlot=state.activeSlot=="B" and "B" or "A"
    state.imageCommit=state.imageCommit or state.commit
    state.repoCommit=state.repoCommit or state.commit
    return state
  end

  local function saveState(state)
    ensureDir(CFG.root:gsub("^/",""))
    return writeAll(join(CFG.root,"state.json"),textutils.serializeJSON(state))
  end

  local function activeRoot(state)
    state=state or loadState()
    return join(CFG.root,state.activeSlot or "A")
  end

  local function cacheUsable(state)
    local root=activeRoot(state):gsub("^/","")
    return fs.exists(fs.combine(root,"kernel/init.lua"))
      and fs.exists(fs.combine(root,"usr/lib/cclua/services/managerd.lua"))
      and fs.exists(fs.combine(root,".manifest.json"))
  end

  local function installedCommit()
    return readText("/var/lib/cclua/installed-commit") or machine.image_commit or "unknown"
  end

  local function runtimeSnapshot()
    local state=loadState()
    return {
      schema=1,
      state=runtime.state,
      progress=runtime.progress,
      total=runtime.total,
      current_action=runtime.currentAction,
      current_file=runtime.currentFile,
      last_error=runtime.lastError,
      last_check=runtime.lastCheck,
      downloaded_bytes=runtime.downloadedBytes,
      delta=runtime.delta,
      repo=CFG.owner.."/"..CFG.repo,
      ref=CFG.ref,
      installed_commit=installedCommit(),
      image_commit=state.imageCommit or state.commit,
      repo_commit=state.repoCommit,
      active_slot=state.activeSlot,
      files=state.files,
      bytes=state.bytes,
      node_count=(function() local n=0 for _ in pairs(runtime.nodes) do n=n+1 end return n end)(),
      poll_seconds=CFG.pollSeconds,
      announce_seconds=CFG.announceSeconds,
      timestamp=os.epoch and os.epoch("utc") or 0,
    }
  end

  local function writeRuntime()
    config.write_json("/var/lib/cclua/manager-state.json",runtimeSnapshot())
  end

  local function writeUpdateState(stateName,extra)
    local state=loadState()
    local payload={
      schema=1,
      state=stateName,
      current_commit=installedCommit(),
      available_commit=state.imageCommit or state.commit,
      repo_commit=state.repoCommit,
      active_slot=state.activeSlot,
      progress=runtime.progress,
      total=runtime.total,
      current_action=runtime.currentAction,
      current_file=runtime.currentFile,
      delta=runtime.delta,
      manager_state=runtime.state,
      timestamp=os.epoch and os.epoch("utc") or 0,
    }
    for k,v in pairs(extra or {}) do payload[k]=v end
    config.write_json("/var/lib/cclua/update-state.json",payload)
  end

  local function setRuntime(stateName,err)
    runtime.state=stateName
    runtime.lastError=err
    writeRuntime()
    writeUpdateState(stateName,{error=err})
  end

  local function request(url)
    local h,err=http.get(url,{
      ["User-Agent"]="CCLUA-LINUX/"..tostring(os.getComputerID()),
      ["Accept"]="application/vnd.github+json",
      ["X-GitHub-Api-Version"]="2022-11-28",
    })
    if not h then return nil,err or "HTTP request failed" end
    local code=h.getResponseCode and h.getResponseCode() or 200
    local body=h.readAll()
    h.close()
    if code<200 or code>=300 then
      return nil,"HTTP "..tostring(code)..": "..tostring(body):sub(1,160)
    end
    return body
  end

  local function requestJson(url)
    local body,err=request(url)
    if not body then return nil,err end
    local ok,data=pcall(textutils.unserializeJSON,body)
    if not ok or type(data)~="table" then return nil,"invalid JSON" end
    return data
  end

  local function repoApi(path)
    return "https://api.github.com/repos/"..CFG.owner.."/"..CFG.repo.."/"..path
  end

  local function rawUrl(sha,path)
    return "https://raw.githubusercontent.com/"..CFG.owner.."/"..CFG.repo.."/"..sha.."/"..path
  end

  local function currentCommit()
    -- Use GitHub's lightweight Atom feed for frequent development checks so
    -- we do not consume the REST API rate limit every few seconds.
    local bucket=math.floor(((os.epoch and os.epoch("utc")) or 0)/5000)
    local feedUrl="https://github.com/"..CFG.owner.."/"..CFG.repo.."/commits/"..textutils.urlEncode(CFG.ref)..".atom?cclua="..tostring(bucket)
    local feed=request(feedUrl)
    if feed then
      local sha=feed:match("Grit::Commit/([0-9a-fA-F]+)</id>")
        or feed:match("/commit/([0-9a-fA-F]+)")
      if sha and #sha>=40 then return sha:lower() end
    end

    local obj,err=requestJson(repoApi("commits/"..textutils.urlEncode(CFG.ref)))
    if not obj then return nil,err end
    return obj.sha
  end

  local function getTree(sha)
    local obj,err=requestJson(repoApi("git/trees/"..sha.."?recursive=1"))
    if not obj then return nil,err end
    if obj.truncated then return nil,"GitHub tree response truncated" end
    return obj.tree or {}
  end

  local function sourceManifest(tree,commit)
    local manifest={schema=1,commit=commit,repo_commit=commit,files={}}
    for _,item in ipairs(tree or {}) do
      if item.type=="blob" and type(item.path)=="string" and item.path:sub(1,4)=="src/" then
        local rel=item.path:sub(5)
        manifest.files[rel]={sha=item.sha,size=item.size or 0}
      end
    end
    return manifest
  end

  local function desktop_only(rel)
    local libPrefix="usr/lib/cclua/desktop/"
    local sharePrefix="usr/share/cclua/desktop/"
    if rel:sub(1,#libPrefix)==libPrefix then return true end
    if rel:sub(1,#sharePrefix)==sharePrefix then return true end
    if rel=="usr/share/cclua/ubuntu-desktop-packages.json" then return true end
    return rel=="usr/bin/cclua-desktop.lua"
      or rel=="usr/bin/cclua-files.lua"
      or rel=="usr/bin/gnome-shell.lua"
      or rel=="usr/bin/gnome-terminal.lua"
      or rel=="usr/bin/nautilus.lua"
  end

  local function manager_only(rel)
    return rel=="usr/lib/cclua/services/managerd.lua"
  end

  local function desktop_role(role)
    role=tostring(role or "")
    return role=="desktop-client" or role:find("desktop",1,true)~=nil
  end

  local function manager_role(role)
    role=tostring(role or "")
    return role=="manager" or role=="network-manager" or role=="linux-network"
  end

  local function manifest_id(manifest,role)
    local keys={}
    for rel in pairs(manifest.files or {}) do keys[#keys+1]=rel end
    table.sort(keys)

    -- Two small integer rolling hashes are enough for an image identity while
    -- staying inside Lua's exact integer range on CC:Tweaked's number model.
    local h1,h2=104729,130363
    local function feed(h,mul,s)
      for i=1,#s do h=(h*mul+s:byte(i))%2147483647 end
      return h
    end
    h1=feed(h1,131,tostring(role or "server"))
    h2=feed(h2,137,tostring(role or "server"))
    for _,rel in ipairs(keys) do
      local meta=manifest.files[rel] or {}
      local line=rel.."="..tostring(meta.sha or "")..":"..tostring(meta.size or 0).."\n"
      h1=feed(h1,131,line)
      h2=feed(h2,137,line)
    end
    return ("img-%08x%08x"):format(h1,h2)
  end

  local function role_manifest(manifest,role)
    local kind=manager_role(role) and "manager" or (desktop_role(role) and "desktop" or "server")
    local out={
      schema=2,
      role=kind,
      repo_commit=manifest.repo_commit or manifest.commit,
      files={}
    }
    for rel,meta in pairs(manifest.files or {}) do
      local include=false
      if kind=="manager" then
        include=not desktop_only(rel)
      elseif kind=="desktop" then
        include=not manager_only(rel)
      else
        include=not desktop_only(rel) and not manager_only(rel)
      end
      if include then out.files[rel]=meta end
    end
    out.commit=manifest_id(out,out.role)
    return out
  end

  local function readManifest(slot,state)
    local raw=readAll(join(slot,".manifest.json"))
    if raw then
      local ok,data=pcall(textutils.unserializeJSON,raw)
      if ok and type(data)=="table" and type(data.files)=="table" then return data end
    end
    local prior=state and (state.imageCommit or state.commit)
    if prior then
      local tree=getTree(prior)
      if tree then return sourceManifest(tree,prior) end
    end
    return {schema=1,commit=prior,files={}}
  end

  local function removeTree(path)
    path=tostring(path):gsub("^/","")
    if fs.exists(path) then fs.delete(path) end
  end

  local function calculateDelta(previous,nextManifest)
    local added,changed,removed,unchanged={},{},{},{}
    for rel,meta in pairs(nextManifest.files or {}) do
      local old=previous.files and previous.files[rel] or nil
      if not old then
        added[#added+1]=rel
      elseif old.sha~=meta.sha then
        changed[#changed+1]=rel
      else
        unchanged[#unchanged+1]=rel
      end
    end
    for rel in pairs(previous.files or {}) do
      if not nextManifest.files[rel] then removed[#removed+1]=rel end
    end
    table.sort(added);table.sort(changed);table.sort(removed);table.sort(unchanged)
    return added,changed,removed,unchanged
  end

  local function yieldBrief()
    if ctx.kernel and ctx.kernel.scheduler and ctx.kernel.scheduler.sleep then
      ctx.kernel.scheduler.sleep(0)
    else
      coroutine.yield("wait_event")
    end
  end

  local function stageCommit(head,tree,state,rebuild)
    local active=activeRoot(state)
    local inactiveName=state.activeSlot=="A" and "B" or "A"
    local slot=join(CFG.root,inactiveName)
    local nextManifest=sourceManifest(tree,head)
    local previous=rebuild and {schema=1,commit=nil,files={}} or readManifest(active,state)
    local added,changed,removed,unchanged=calculateDelta(previous,nextManifest)

    local bootChanged=rebuild==true
    if not bootChanged then
      for _,list in ipairs({added,changed,removed}) do
        for _,rel in ipairs(list) do
          if not desktop_only(rel) then
            bootChanged=true
            break
          end
        end
        if bootChanged then break end
      end
    end
    local previousImage=state.imageCommit or state.commit or installedCommit()

    runtime.delta={
      added=#added,changed=#changed,removed=#removed,unchanged=#unchanged,
      boot_changed=bootChanged
    }
    runtime.total=#added+#changed+#removed
    runtime.progress=0
    runtime.downloadedBytes=0

    if runtime.total==0 then
      state.repoCommit=head
      state.lastDelta={
        added=0,changed=0,removed=0,unchanged=#unchanged,downloadedBytes=0
      }
      saveState(state)
      runtime.currentAction=nil
      runtime.currentFile=nil
      setRuntime("CURRENT")
      return state,false
    end

    runtime.currentAction=rebuild and "REBUILD" or "STAGE"
    runtime.currentFile=rebuild and "rebuilding manager image cache" or "copying last-known-good image"
    setRuntime("STAGING")

    removeTree(slot)
    ensureDir(CFG.root:gsub("^/",""))
    if not rebuild and fs.exists(active:gsub("^/","")) then
      local ok,copyErr=pcall(fs.copy,active:gsub("^/",""),slot:gsub("^/",""))
      if not ok then return nil,"stage copy failed: "..tostring(copyErr) end
    else
      ensureDir(slot:gsub("^/",""))
    end

    local manifestPath=join(slot,".manifest.json")
    local commitPath=join(slot,".commit")
    if fs.exists(manifestPath:gsub("^/","")) then fs.delete(manifestPath:gsub("^/","")) end
    if fs.exists(commitPath:gsub("^/","")) then fs.delete(commitPath:gsub("^/","")) end

    local function advance(action,rel)
      runtime.currentAction=action
      runtime.currentFile=rel
      runtime.progress=runtime.progress+1
      writeRuntime()
      writeUpdateState(action=="REMOVE" and "STAGING" or "DOWNLOADING")
      yieldBrief()
    end

    for _,rel in ipairs(removed) do
      local target=join(slot,rel):gsub("^/","")
      if fs.exists(target) then fs.delete(target) end
      advance("REMOVE",rel)
    end

    local function downloadFile(rel,action)
      runtime.currentAction=action
      runtime.currentFile=rel
      writeRuntime()
      writeUpdateState("DOWNLOADING")
      local body,ferr=request(rawUrl(head,"src/"..rel))
      if not body then return nil,"download src/"..rel..": "..tostring(ferr) end
      local ok,werr=writeAll(join(slot,rel),body)
      if not ok then return nil,"write "..rel..": "..tostring(werr) end
      runtime.downloadedBytes=runtime.downloadedBytes+#body
      runtime.progress=runtime.progress+1
      writeRuntime()
      writeUpdateState("DOWNLOADING")
      yieldBrief()
      return true
    end

    for _,rel in ipairs(changed) do
      local ok,err=downloadFile(rel,"CHANGE")
      if not ok then removeTree(slot);return nil,err end
    end
    for _,rel in ipairs(added) do
      local ok,err=downloadFile(rel,"ADD")
      if not ok then removeTree(slot);return nil,err end
    end

    runtime.currentAction="VERIFY"
    runtime.currentFile="manifest and image metadata"
    setRuntime("VERIFYING")

    local ok,merr=writeAll(manifestPath,textutils.serializeJSON(nextManifest))
    if not ok then removeTree(slot);return nil,merr end

    -- The cache slot always advances to the latest repository payload, but
    -- its boot commit only advances when a common/server file changed.
    local bootCommit=bootChanged and head or previousImage
    writeAll(commitPath,tostring(bootCommit).."\n")

    local files,bytes=0,0
    for _,meta in pairs(nextManifest.files) do
      files=files+1
      bytes=bytes+(meta.size or 0)
    end

    state.activeSlot=inactiveName
    state.imageCommit=bootChanged and head or previousImage
    state.repoCommit=head
    state.commit=state.imageCommit
    state.ref=CFG.ref
    state.files=files
    state.bytes=bytes
    state.updatedAt=os.epoch and os.epoch("utc") or 0
    state.lastDelta={
      added=#added,changed=#changed,removed=#removed,unchanged=#unchanged,
      downloadedBytes=runtime.downloadedBytes,bootChanged=bootChanged
    }
    local saved,serr=saveState(state)
    if not saved then return nil,serr end

    runtime.progress=runtime.total
    runtime.currentAction=nil
    runtime.currentFile=nil
    setRuntime("READY")
    return state,true
  end

  local function sync(force)
    runtime.lastCheck=os.date and os.date("%H:%M:%S") or tostring(os.epoch("utc"))
    runtime.currentAction="CHECK"
    runtime.currentFile="GitHub HEAD"
    runtime.progress=0
    runtime.total=0
    runtime.lastError=nil
    setRuntime("CHECKING")

    local head,err=currentCommit()
    if not head then
      setRuntime("DEGRADED",err)
      return nil,err
    end

    local state=loadState()
    local usable=cacheUsable(state)
    if not force and state.repoCommit==head and usable then
      runtime.delta={added=0,changed=0,removed=0,unchanged=state.files or 0}
      runtime.currentAction=nil
      runtime.currentFile=nil
      setRuntime(installedCommit()==(state.imageCommit or state.commit) and "CURRENT" or "READY")
      return state,false
    end

    runtime.currentAction="TREE"
    runtime.currentFile="comparing Git blob SHAs"
    writeRuntime()

    local tree,terr=getTree(head)
    if not tree then
      setRuntime("DEGRADED",terr)
      return nil,terr
    end

    local nextState,changedOrErr=stageCommit(head,tree,state,not usable)
    if not nextState then
      setRuntime("DEGRADED",changedOrErr)
      return nil,changedOrErr
    end
    return nextState,changedOrErr==true
  end

  local function openModems()
    local opened={}
    for _,name in ipairs(peripheral.getNames()) do
      if peripheral.hasType(name,"modem") then
        local ok=pcall(rednet.open,name)
        if ok then opened[#opened+1]=name end
      end
    end
    if #opened>0 then pcall(rednet.host,CFG.protocol,machine.hostname or "LINUX_NETWORK") end
    return opened
  end

  local function flushPeers()
    if not runtime.peersDirty then return false end
    local out={}
    for _,node in pairs(runtime.nodes) do out[#out+1]=node end
    table.sort(out,function(a,b)return (a.id or 9999)<(b.id or 9999) end)

    local ok,err=config.write_json("/var/lib/cclua/manager-peers.json",{
      schema=1,
      timestamp=os.epoch and os.epoch("utc") or 0,
      nodes=out
    })
    if not ok then
      ctx.kernel.log.write("warning","managerd","peer snapshot write failed",{
        error=tostring(err),nodes=#out
      },ctx.process.pid)
      return false
    end

    runtime.peersDirty=false
    return true
  end

  local function rememberNode(sender,msg)
    local n=runtime.nodes[sender] or {}
    n.id=sender
    n.last_seen=os.epoch and os.epoch("utc") or 0
    if type(msg)=="table" then
      n.hostname=msg.hostname or (msg.status and msg.status.hostname) or n.hostname
      n.role=msg.role or (msg.status and msg.status.role) or n.role
      if type(msg.status)=="table" then
        n.status=n.status or {}
        for k,v in pairs(msg.status) do n.status[k]=v end
      end
    end
    runtime.nodes[sender]=n
    runtime.peersDirty=true
  end

  local function active_role_manifest(role)
    local raw=readAll(join(activeRoot(),".manifest.json"))
    local ok,manifest=pcall(textutils.unserializeJSON,raw or "")
    if not ok or type(manifest)~="table" or type(manifest.files)~="table" then
      return nil
    end
    return role_manifest(manifest,role)
  end

  local function managerStatus(role)
    local state=loadState()
    local roleRequested=role~=nil and tostring(role)~=""
    local manifest=roleRequested and active_role_manifest(role) or nil
    local files,bytes=0,0
    if manifest then
      for _,meta in pairs(manifest.files or {}) do
        files=files+1
        bytes=bytes+(tonumber(meta.size) or 0)
      end
    end
    return {
      repo=CFG.owner.."/"..CFG.repo,
      ref=CFG.ref,
      role=manifest and manifest.role or (roleRequested and (desktop_role(role) and "desktop" or "server") or machine.role),
      commit=manifest and manifest.commit or (state.imageCommit or state.commit),
      repoCommit=state.repoCommit,
      activeSlot=state.activeSlot,
      files=manifest and files or state.files,
      bytes=manifest and bytes or state.bytes,
      managerState=runtime.state,
      installedCommit=installedCommit(),
      delta=runtime.delta,
      progress=runtime.progress,
      total=runtime.total,
      currentAction=runtime.currentAction,
      currentFile=runtime.currentFile,
      lastError=runtime.lastError,
    }
  end

  local function fleetSnapshot()
    local nodes={}
    for _,node in pairs(runtime.nodes) do
      nodes[#nodes+1]=node
    end
    table.sort(nodes,function(a,b)
      local ah=tostring(a.hostname or "")
      local bh=tostring(b.hostname or "")
      if ah~=bh then return ah<bh end
      return (a.id or 9999)<(b.id or 9999)
    end)
    return {
      schema=1,
      manager=managerStatus(),
      nodes=nodes,
      timestamp=os.epoch and os.epoch("utc") or 0
    }
  end

  local function announceImage(reason)
    local status=managerStatus()
    rednet.broadcast({
      protocol=CFG.protocol,
      op="image_available",
      ok=true,
      reason=reason or "heartbeat",
      status=status
    },CFG.protocol)
  end

  local function safeRel(path)
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

  local function serve(sender,msg)
    if type(msg)~="table" or msg.protocol~=CFG.protocol then return end
    rememberNode(sender,msg)

    if msg.op=="status" then
      rednet.send(sender,{protocol=CFG.protocol,op="status",ok=true,status=managerStatus(msg.role)},CFG.protocol)

    elseif msg.op=="manifest" then
      local manifest=active_role_manifest(msg.role)
      if manifest then
        rednet.send(sender,{protocol=CFG.protocol,op="manifest",ok=true,manifest=manifest,status=managerStatus(msg.role)},CFG.protocol)
      else
        rednet.send(sender,{protocol=CFG.protocol,op="manifest",ok=false,error="active image manifest unavailable"},CFG.protocol)
      end

    elseif msg.op=="read_chunk" and type(msg.path)=="string" then
      local rel=safeRel(msg.path)
      if not rel then
        rednet.send(sender,{protocol=CFG.protocol,op="read_chunk",ok=false,error="invalid path"},CFG.protocol)
        return
      end
      local data=readAll(join(activeRoot(),rel))
      if data==nil then
        rednet.send(sender,{protocol=CFG.protocol,op="read_chunk",ok=false,error="file not found",path=rel},CFG.protocol)
        return
      end
      local offset=math.max(0,tonumber(msg.offset) or 0)
      local size=math.max(1,math.min(12000,tonumber(msg.size) or 12000))
      local chunk=data:sub(offset+1,offset+size)
      local nextOffset=offset+#chunk
      rednet.send(sender,{
        protocol=CFG.protocol,op="read_chunk",ok=true,path=rel,
        offset=offset,next_offset=nextOffset,size=#data,data=chunk,eof=nextOffset>=#data
      },CFG.protocol)

    elseif msg.op=="read" and type(msg.path)=="string" then
      local rel=safeRel(msg.path)
      if not rel then
        rednet.send(sender,{protocol=CFG.protocol,op="read",ok=false,error="invalid path"},CFG.protocol)
        return
      end
      local data=readAll(join(activeRoot(),rel))
      rednet.send(sender,{protocol=CFG.protocol,op="read",ok=data~=nil,path=rel,data=data},CFG.protocol)

    elseif msg.op=="sync" then
      local state,changedOrErr=sync(msg.force==true)
      rednet.send(sender,{
        protocol=CFG.protocol,op="sync",ok=state~=nil,
        changed=state and changedOrErr==true or false,
        error=state and nil or changedOrErr,
        status=state and managerStatus() or nil
      },CFG.protocol)
    end
  end

  local function serveFleet(sender,msg)
    if type(msg)~="table" or msg.protocol~=CFG.fleetProtocol then return end
    if msg.op=="fleet_status" then
      rednet.send(sender,{
        protocol=CFG.fleetProtocol,
        op="fleet_status",
        ok=true,
        snapshot=fleetSnapshot()
      },CFG.fleetProtocol)
    end
  end

  local function maybeActivate(state,changed)
    if not changed then return end
    local image=state.imageCommit or state.commit
    if installedCommit()==image then
      setRuntime("CURRENT")
      return
    end
    if machine.auto_apply_updates==false then return end

    local now=os.epoch and os.epoch("utc") or 0
    config.write_json("/var/lib/cclua/boot.json",{
      schema=1,
      pending=true,
      pending_slot=state.activeSlot,
      pending_commit=image,
      requested_at=now,
    })

    runtime.pendingRebootCommit=image
    runtime.rebootEarliest=now+(tonumber(machine.manager_reboot_min_ms) or 1500)
    runtime.rebootDeadline=now+(tonumber(machine.manager_reboot_max_ms) or 12000)
    runtime.currentAction="SERVE"
    runtime.currentFile="waiting for node staging"
    setRuntime("ACTIVATING")
    ctx.kernel.log.write("info","managerd","staged manager image; serving nodes before reboot",{
      commit=image,slot=state.activeSlot,
      earliest=runtime.rebootEarliest,deadline=runtime.rebootDeadline
    },ctx.process.pid)
    announceImage("manager-activation-pending")
  end

  local function nodesReadyFor(commit)
    local now=os.epoch and os.epoch("utc") or 0
    local online,ready=0,0
    for _,node in pairs(runtime.nodes) do
      local age=now-(node.last_seen or 0)
      if age<10000 and node.id~=os.getComputerID() then
        online=online+1
        local st=node.status or {}
        local upd=st.update or {}
        local current=tostring(st.current_commit or upd.current_commit or "")
        local target=tostring(upd.target_commit or upd.available_commit or "")
        local phase=tostring(upd.state or "")
        local ok=current==commit
          or (target==commit and (phase=="READY" or phase=="ACTIVATING" or phase=="CURRENT"))
        if ok then ready=ready+1 end
      end
    end
    return online==0 or ready>=online,online,ready
  end

  local function checkManagerActivation()
    if not runtime.pendingRebootCommit then return false end
    local now=os.epoch and os.epoch("utc") or 0
    local ready,online,readyCount=nodesReadyFor(runtime.pendingRebootCommit)
    local deadline=runtime.rebootDeadline and now>=runtime.rebootDeadline
    local earliest=runtime.rebootEarliest and now>=runtime.rebootEarliest

    runtime.currentAction="SERVE"
    runtime.currentFile=("nodes staged %d/%d"):format(readyCount,online)
    writeRuntime()
    writeUpdateState("ACTIVATING",{
      node_ready=readyCount,node_online=online,
      pending_commit=runtime.pendingRebootCommit
    })

    if (earliest and ready) or deadline then
      ctx.kernel.log.write("info","managerd","node staging complete; rebooting manager",{
        commit=runtime.pendingRebootCommit,online=online,ready=readyCount,deadline=deadline
      },ctx.process.pid)
      runtime.currentAction="REBOOT"
      runtime.currentFile=deadline and "activation deadline reached" or "all online nodes staged"
      writeRuntime()
      os.reboot()
      return true
    end
    return false
  end

  local opened=openModems()
  ctx.unit.details={protocol=CFG.protocol,modems=opened,repo=CFG.owner.."/"..CFG.repo,ref=CFG.ref}
  ctx.kernel.log.write("info","managerd","CCLUA network manager online",ctx.unit.details,ctx.process.pid)

  local state,changed=sync(false)
  if state then
    announceImage(changed and "github-update" or "startup")
    maybeActivate(state,changed==true)
  end

  local poll=os.startTimer(CFG.pollSeconds)
  local now0=os.epoch and os.epoch("utc") or 0
  local nextAnnounce=now0+math.floor(CFG.announceSeconds*1000)
  local nextPeerFlush=now0+2000
  local modemRefreshTimer=nil
  while true do
    local ev,a,b,c=coroutine.yield("wait_event",{"timer","rednet_message","cclua_manager_sync","peripheral","peripheral_detach","terminate"})
    if ev=="timer" and a==poll then
      if runtime.pendingRebootCommit then
        announceImage("activation-pending")
      else
        local nextState,didChange=sync(false)
        if nextState then
          announceImage(didChange and "github-update" or "poll")
          maybeActivate(nextState,didChange==true)
        end
      end
      poll=os.startTimer(CFG.pollSeconds)
    elseif ev=="rednet_message" and c==CFG.protocol then
      serve(a,b)
    elseif ev=="rednet_message" and c==CFG.fleetProtocol then
      serveFleet(a,b)
    elseif ev=="cclua_manager_sync" then
      local nextState,didChange=sync(a==true)
      if nextState then maybeActivate(nextState,didChange==true) end
    elseif ev=="peripheral" or ev=="peripheral_detach" then
      if modemRefreshTimer and os.cancelTimer then pcall(os.cancelTimer,modemRefreshTimer) end
      modemRefreshTimer=os.startTimer(0.40)
    elseif ev=="timer" and modemRefreshTimer and a==modemRefreshTimer then
      modemRefreshTimer=nil
      opened=openModems()
      ctx.unit.details.modems=opened
    end

    -- Housekeeping uses wall-clock deadlines instead of dedicated timers.
    -- Native APIs such as http.get() temporarily narrow this process' event
    -- filter and can consume unrelated timer events before managerd sees them.
    local now=os.epoch and os.epoch("utc") or 0

    if now>=nextPeerFlush then
      local wrote=true
      if runtime.peersDirty then wrote=flushPeers() end
      nextPeerFlush=now+(wrote==false and 1000 or 2000)
    end

    if now>=nextAnnounce then
      announceImage(runtime.pendingRebootCommit and "activation-pending" or "heartbeat")
      nextAnnounce=now+math.floor(CFG.announceSeconds*1000)
    end

    -- Coordination must not depend on a dedicated timer event. Any manager
    -- event (node heartbeat, transfer request, poll, peripheral change) can
    -- advance activation.
    if runtime.pendingRebootCommit then checkManagerActivation() end
  end
end
