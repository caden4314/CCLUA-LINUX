return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local net=dofile("/usr/lib/cclua/net.lua")
  local drivers=dofile("/usr/lib/cclua/drivers.lua")
  local sdkModule=dofile("/usr/lib/cclua/sdk.lua")
  local machine=config.machine()
  local protocol="cclua-apphost-v1"
  local managerProtocol="cclua-manager-v1"
  local managerId=tonumber(machine.manager_computer_id) or 0
  local root="/srv/cclua/apps"
  local stagingRoot="/var/lib/cclua/app-staging"
  local backupRoot="/var/lib/cclua/app-backup"
  local running={}
  local deployments={}

  local function host(path) return tostring(path):gsub("^/","") end

  local function ensure(path)
    path=host(path)
    if path=="" or fs.exists(path) then return end
    local parent=fs.getDir(path)
    if parent~="" and not fs.exists(parent) then ensure(parent) end
    fs.makeDir(path)
  end

  local function safe_app(name)
    if type(name)~="string" or name=="" then return nil end
    if name=="." or name==".." then return nil end
    if not name:match("^[%w][%w%._%-]*$") then return nil end
    return name
  end

  local function safe_rel(path)
    if type(path)~="string" or path=="" then return nil end
    path=path:gsub("\\","/")
    if path:sub(1,1)=="/" then return nil end
    local parts={}
    for seg in path:gmatch("[^/]+") do
      if seg=="" or seg=="." or seg==".." then return nil end
      parts[#parts+1]=seg
    end
    if #parts==0 then return nil end
    return table.concat(parts,"/")
  end

  local function app_root(name) return root.."/"..name end
  local function app_path(name) return app_root(name).."/app.lua" end
  local function stage_root(name) return stagingRoot.."/"..name end
  local function backup_root(name) return backupRoot.."/"..name end

  local function read_json(path,default)
    return config.read_json(path,default)
  end

  local function write_json(path,value)
    return config.write_json(path,value)
  end

  local function role_class()
    local image=tostring(machine.image or "")
    if machine.role=="desktop-client" or image:find("desktop",1,true) then return "desktop" end
    return "server"
  end

  local function manifest_for(name,base)
    base=base or app_root(name)
    local manifest=read_json(base.."/app.json",nil)
    if type(manifest)~="table" then
      manifest={
        schema=1,name=name,entrypoint="app.lua",
        description="Legacy CCLUA application",roles={"server","desktop"},
        requires={},
      }
    end
    manifest.name=tostring(manifest.name or name)
    manifest.entrypoint=safe_rel(manifest.entrypoint or "app.lua") or "app.lua"
    manifest.roles=type(manifest.roles)=="table" and manifest.roles or {"server","desktop"}
    manifest.requires=type(manifest.requires)=="table" and manifest.requires or {}
    return manifest
  end

  local function role_allowed(manifest)
    local class=role_class()
    for _,r in ipairs(manifest.roles or {}) do
      r=tostring(r)
      if r=="*" or r==class or r==tostring(machine.role) then return true end
    end
    return false
  end

  local function missing_capabilities(manifest)
    local caps=drivers.capabilities()
    local have={}
    for _,cap in ipairs(caps or {}) do have[cap]=true end
    local missing={}
    for _,cap in ipairs(manifest.requires or {}) do
      cap=tostring(cap)
      if not have[cap] then missing[#missing+1]=cap end
    end
    table.sort(missing)
    return missing
  end

  local function validate_manifest(name,base)
    local manifest=manifest_for(name,base)
    if manifest.name~=name then return nil,"manifest name does not match deployment name" end
    if not role_allowed(manifest) then
      return nil,("application does not support role %s (%s)"):format(
        tostring(machine.role),role_class())
    end
    local entry=host((base or app_root(name)).."/"..manifest.entrypoint)
    if not fs.exists(entry) or fs.isDir(entry) then
      return nil,"manifest entrypoint missing: "..manifest.entrypoint
    end
    local missing=missing_capabilities(manifest)
    if #missing>0 then
      return nil,"missing capabilities: "..table.concat(missing,", ")
    end
    return manifest
  end

  local function dir_stats(path)
    path=host(path)
    local files,bytes=0,0
    if not fs.exists(path) then return files,bytes end
    local function walk(p)
      for _,name in ipairs(fs.list(p)) do
        local f=fs.combine(p,name)
        if fs.isDir(f) then walk(f)
        else
          files=files+1
          bytes=bytes+fs.getSize(f)
        end
      end
    end
    walk(path)
    return files,bytes
  end

  local function deployment_meta(name)
    return read_json(app_root(name).."/.deployment.json",{})
  end

  local function list_apps()
    ensure(root)
    local out={}
    for _,name in ipairs(fs.list(host(root))) do
      local base=app_root(name)
      if fs.isDir(host(base)) then
        local manifest=manifest_for(name,base)
        local entry=host(base.."/"..manifest.entrypoint)
        if fs.exists(entry) and not fs.isDir(entry) then
          local pid=running[name]
          local proc=pid and ctx.kernel.process.get(pid) or nil
          if not proc or proc.state=="exited" or proc.state=="killed" or proc.state=="crashed" then
            running[name]=nil
            pid=nil
          end
          local meta=deployment_meta(name)
          local missing=missing_capabilities(manifest)
          local compatible=role_allowed(manifest) and #missing==0
          out[#out+1]={
            name=name,pid=pid,state=pid and "running" or "stopped",
            version=manifest.version or meta.version,
            description=manifest.description,
            entrypoint=manifest.entrypoint,
            roles=manifest.roles,requires=manifest.requires,
            compatible=compatible,missing_capabilities=missing,
            commit=meta.commit,deployed_at=meta.deployed_at,
            files=meta.files,bytes=meta.bytes
          }
        end
      end
    end
    table.sort(out,function(a,b)return a.name<b.name end)
    return out
  end

  local function state()
    local s={
      schema=2,
      hostname=machine.hostname,
      computer_id=os.getComputerID(),
      role=machine.role,
      apps=list_apps(),
      deployments=(function()
        local out={}
        for name,d in pairs(deployments) do
          out[#out+1]={
            app=name,files=d.receivedFiles,expected_files=d.expectedFiles,
            bytes=d.receivedBytes,expected_bytes=d.expectedBytes,
            current_file=d.currentFile
          }
        end
        return out
      end)(),
      timestamp=os.epoch and os.epoch("utc") or 0
    }
    config.write_json("/var/lib/cclua/apphost.json",s)
    return s
  end

  local function start_app(name)
    name=safe_app(name)
    if not name then return nil,"invalid app name" end

    if running[name] then
      local p=ctx.kernel.process.get(running[name])
      if p and p.state~="exited" and p.state~="killed" and p.state~="crashed" then
        return true,running[name]
      end
      running[name]=nil
    end

    local manifest,manifestErr=validate_manifest(name,app_root(name))
    if not manifest then return nil,manifestErr or ("app not installed: "..name) end
    local path=app_root(name).."/"..manifest.entrypoint

    local proc,err=ctx.kernel.process.create{
      ppid=ctx.process.pid,
      name="app:"..name,
      uid=0,gid=0,cwd=app_root(name),
      capabilities=ctx.kernel.capabilities.root(),
      argv={path}
    }
    if not proc then return nil,err end

    running[name]=proc.pid
    ctx.kernel.scheduler:add(proc,function()
      local ok,mod=pcall(dofile,path)
      if not ok then
        ctx.kernel.log.write("error","apphostd","app load failed",{app=name,error=tostring(mod)},proc.pid)
        running[name]=nil
        return 1
      end
      local okRun,res
      local appCtx={
        kernel=ctx.kernel,process=proc,app=name,
        manifest=manifest,drivers=drivers,
      }
      appCtx.sdk=sdkModule.open(appCtx,manifest)
      if type(mod)=="table" and type(mod.main)=="function" then
        okRun,res=pcall(mod.main,appCtx,{})
      elseif type(mod)=="function" then
        okRun,res=pcall(mod,appCtx)
      else
        okRun,res=true,0
      end
      if not okRun then
        ctx.kernel.log.write("error","apphostd","app crashed",{app=name,error=tostring(res)},proc.pid)
        running[name]=nil
        return 1
      end
      running[name]=nil
      return tonumber(res) or 0
    end)

    ctx.kernel.log.write("info","apphostd","app started",{app=name,pid=proc.pid},ctx.process.pid)
    return true,proc.pid
  end

  local function stop_app(name)
    name=safe_app(name)
    if not name then return nil,"invalid app name" end
    local pid=running[name]
    if not pid then return true end
    local p=ctx.kernel.process.get(pid)
    if p and p.state~="exited" and p.state~="killed" and p.state~="crashed" then
      ctx.kernel.process.exit(p,143,"killed")
      if os.queueEvent then os.queueEvent("cclua_process_exit",p.pid,p.exit_code,"killed") end
    end
    running[name]=nil
    ctx.kernel.log.write("info","apphostd","app stopped",{app=name,pid=pid},ctx.process.pid)
    return true
  end

  local function deploy_begin(msg)
    local name=safe_app(msg.app)
    if not name then return nil,"invalid app name" end
    local stage=host(stage_root(name))
    if fs.exists(stage) then fs.delete(stage) end
    ensure(stage)

    deployments[name]={
      expectedFiles=tonumber(msg.files) or 0,
      expectedBytes=tonumber(msg.bytes) or 0,
      receivedFiles=0,receivedBytes=0,
      currentFile=nil,currentExpected=0,currentReceived=0,
      version=msg.version,commit=msg.commit,
      autostart=msg.autostart==true,
      startedAt=os.epoch and os.epoch("utc") or 0
    }
    ctx.kernel.log.write("info","apphostd","deployment started",{
      app=name,files=deployments[name].expectedFiles,bytes=deployments[name].expectedBytes,
      version=msg.version
    },ctx.process.pid)
    return true
  end

  local function deploy_file_begin(msg)
    local name=safe_app(msg.app)
    local rel=safe_rel(msg.path)
    local d=name and deployments[name] or nil
    if not d then return nil,"no active deployment" end
    if not rel then return nil,"invalid file path" end

    local path=host(stage_root(name).."/"..rel)
    ensure(fs.getDir(path))
    if fs.exists(path) then fs.delete(path) end
    local h,err=fs.open(path,"w")
    if not h then return nil,err or "cannot create file" end
    h.close()

    d.currentFile=rel
    d.currentExpected=tonumber(msg.size) or 0
    d.currentReceived=0
    return true
  end

  local function deploy_chunk(msg)
    local name=safe_app(msg.app)
    local rel=safe_rel(msg.path)
    local d=name and deployments[name] or nil
    if not d then return nil,"no active deployment" end
    if not rel or rel~=d.currentFile then return nil,"unexpected file chunk" end
    if type(msg.data)~="string" then return nil,"invalid chunk" end

    local path=host(stage_root(name).."/"..rel)
    local h,err=fs.open(path,"a")
    if not h then return nil,err or "cannot append file" end
    h.write(msg.data)
    h.close()

    d.currentReceived=d.currentReceived+#msg.data
    d.receivedBytes=d.receivedBytes+#msg.data
    return true,d.currentReceived
  end

  local function deploy_file_end(msg)
    local name=safe_app(msg.app)
    local rel=safe_rel(msg.path)
    local d=name and deployments[name] or nil
    if not d then return nil,"no active deployment" end
    if not rel or rel~=d.currentFile then return nil,"unexpected file completion" end

    local path=host(stage_root(name).."/"..rel)
    local size=fs.exists(path) and fs.getSize(path) or -1
    if size~=d.currentExpected then
      return nil,("size mismatch for %s: got %d expected %d"):format(rel,size,d.currentExpected)
    end

    d.receivedFiles=d.receivedFiles+1
    d.currentFile=nil
    d.currentExpected=0
    d.currentReceived=0
    return true
  end

  local function deploy_abort(name,reason)
    name=safe_app(name)
    if not name then return nil,"invalid app name" end
    local stage=host(stage_root(name))
    if fs.exists(stage) then fs.delete(stage) end
    deployments[name]=nil
    ctx.kernel.log.write("warning","apphostd","deployment aborted",{app=name,reason=reason},ctx.process.pid)
    return true
  end

  local function deploy_commit(msg)
    local name=safe_app(msg.app)
    local d=name and deployments[name] or nil
    if not d then return nil,"no active deployment" end
    if d.currentFile then return nil,"file transfer still active: "..d.currentFile end
    if d.receivedFiles~=d.expectedFiles then
      return nil,("file count mismatch: got %d expected %d"):format(d.receivedFiles,d.expectedFiles)
    end
    if d.receivedBytes~=d.expectedBytes then
      return nil,("byte count mismatch: got %d expected %d"):format(d.receivedBytes,d.expectedBytes)
    end

    local stage=host(stage_root(name))
    local manifest,manifestErr=validate_manifest(name,stage_root(name))
    if not manifest then return nil,"manifest validation failed: "..tostring(manifestErr) end

    stop_app(name)
    local target=host(app_root(name))
    local backup=host(backup_root(name))
    if fs.exists(backup) then fs.delete(backup) end
    if fs.exists(target) then
      ensure(fs.getDir(backup))
      fs.move(target,backup)
    end
    fs.move(stage,target)

    local meta={
      schema=2,app=name,version=manifest.version or d.version,commit=d.commit,
      entrypoint=manifest.entrypoint,roles=manifest.roles,requires=manifest.requires,
      description=manifest.description,
      files=d.receivedFiles,bytes=d.receivedBytes,
      deployed_at=os.epoch and os.epoch("utc") or 0,
      deployed_by=managerId
    }
    write_json(app_root(name).."/.deployment.json",meta)

    deployments[name]=nil
    local pid=nil
    if d.autostart or manifest.autostart==true then
      local ok,res=start_app(name)
      if not ok then
        ctx.kernel.log.write("error","apphostd","deployment committed but autostart failed",{app=name,error=res},ctx.process.pid)
        return nil,"deployed but autostart failed: "..tostring(res)
      end
      pid=res
    end

    ctx.kernel.log.write("info","apphostd","deployment committed",{
      app=name,version=d.version,files=d.receivedFiles,bytes=d.receivedBytes,pid=pid
    },ctx.process.pid)
    return true,pid
  end

  local function rollback_app(name)
    name=safe_app(name)
    if not name then return nil,"invalid app name" end
    local backup=host(backup_root(name))
    if not fs.exists(backup) then return nil,"no rollback version available" end
    stop_app(name)
    local target=host(app_root(name))
    if fs.exists(target) then fs.delete(target) end
    fs.move(backup,target)
    ctx.kernel.log.write("warning","apphostd","app rolled back",{app=name},ctx.process.pid)
    return true
  end

  local function remove_app(name)
    name=safe_app(name)
    if not name then return nil,"invalid app name" end
    stop_app(name)
    local target=host(app_root(name))
    if not fs.exists(target) then return nil,"app not installed" end
    local backup=host(backup_root(name))
    if fs.exists(backup) then fs.delete(backup) end
    ensure(fs.getDir(backup))
    fs.move(target,backup)
    ctx.kernel.log.write("warning","apphostd","app removed to rollback storage",{app=name},ctx.process.pid)
    return true
  end

  local function heartbeat()
    local s=state()
    rednet.send(managerId,{
      protocol=managerProtocol,
      op="status",
      hostname=machine.hostname,
      role=machine.role,
      status={
        hostname=machine.hostname,
        role=machine.role,
        system_state="HEALTHY",
        apps=#s.apps,
        apphost=s,
        processes=#ctx.kernel.process.all(),
        services=(function()
          local n=0
          for _,u in ipairs(ctx.kernel.services:list()) do if u.state=="active" then n=n+1 end end
          return n
        end)()
      }
    },managerProtocol)
  end

  local function reply(id,msg)
    rednet.send(id,msg,protocol)
  end

  local function handle(sender,msg)
    if sender~=managerId then
      ctx.kernel.log.write("warning","apphostd","rejected app command",{sender=sender},ctx.process.pid)
      return
    end
    if type(msg)~="table" or msg.protocol~=protocol then return end

    if msg.op=="status" or msg.op=="list" then
      reply(sender,{protocol=protocol,op=msg.op,ok=true,state=state()})
      return
    end

    if msg.op=="info" then
      local wanted=safe_app(msg.app)
      if not wanted then
        reply(sender,{protocol=protocol,op=msg.op,ok=false,error="invalid app name"})
        return
      end
      local found=nil
      for _,app in ipairs(list_apps()) do
        if app.name==wanted then found=app;break end
      end
      if not found then
        reply(sender,{protocol=protocol,op=msg.op,ok=false,error="app not installed"})
      else
        reply(sender,{protocol=protocol,op=msg.op,ok=true,app=found,state=state()})
      end
      return
    end

    if msg.op=="start" then
      local ok,res=start_app(msg.app)
      reply(sender,{protocol=protocol,op="start",ok=ok==true,error=ok and nil or res,pid=ok and res or nil,state=state()})
      return
    end

    if msg.op=="stop" then
      local ok,err=stop_app(msg.app)
      reply(sender,{protocol=protocol,op="stop",ok=ok==true,error=err,state=state()})
      return
    end

    if msg.op=="restart" then
      stop_app(msg.app)
      local ok,res=start_app(msg.app)
      reply(sender,{protocol=protocol,op="restart",ok=ok==true,error=ok and nil or res,pid=ok and res or nil,state=state()})
      return
    end

    if msg.op=="deploy_begin" then
      local ok,err=deploy_begin(msg)
      reply(sender,{protocol=protocol,op=msg.op,ok=ok==true,error=err})
      return
    end

    if msg.op=="deploy_file_begin" then
      local ok,err=deploy_file_begin(msg)
      reply(sender,{protocol=protocol,op=msg.op,ok=ok==true,error=err})
      return
    end

    if msg.op=="deploy_chunk" then
      local ok,res=deploy_chunk(msg)
      reply(sender,{protocol=protocol,op=msg.op,ok=ok==true,error=ok and nil or res,received=ok and res or nil})
      return
    end

    if msg.op=="deploy_file_end" then
      local ok,err=deploy_file_end(msg)
      reply(sender,{protocol=protocol,op=msg.op,ok=ok==true,error=err})
      return
    end

    if msg.op=="deploy_commit" then
      local ok,res=deploy_commit(msg)
      reply(sender,{protocol=protocol,op=msg.op,ok=ok==true,error=ok and nil or res,pid=ok and res or nil,state=state()})
      return
    end

    if msg.op=="deploy_abort" then
      local ok,err=deploy_abort(msg.app,msg.reason)
      reply(sender,{protocol=protocol,op=msg.op,ok=ok==true,error=err})
      return
    end

    if msg.op=="rollback" then
      local ok,err=rollback_app(msg.app)
      reply(sender,{protocol=protocol,op=msg.op,ok=ok==true,error=err,state=state()})
      return
    end

    if msg.op=="remove" then
      local ok,err=remove_app(msg.app)
      reply(sender,{protocol=protocol,op=msg.op,ok=ok==true,error=err,state=state()})
      return
    end

    reply(sender,{protocol=protocol,op=msg.op,ok=false,error="unknown operation"})
  end

  ensure(root)
  ensure(stagingRoot)
  ensure(backupRoot)
  ensure("/var/lib/cclua")
  net.open_management_modems()
  ctx.unit.details={protocol=protocol,manager_id=managerId,root=root}
  ctx.kernel.log.write("info","apphostd","application host online",ctx.unit.details,ctx.process.pid)
  heartbeat()

  local timer=os.startTimer(5)
  while true do
    local ev,a,b,c=coroutine.yield("wait_event",{"timer","rednet_message","peripheral","terminate"})
    if ev=="timer" and a==timer then
      heartbeat()
      timer=os.startTimer(5)
    elseif ev=="rednet_message" and c==protocol then
      handle(a,b)
    elseif ev=="peripheral" then
      net.open_management_modems()
    end
  end
end
