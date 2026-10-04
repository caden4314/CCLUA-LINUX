return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local net=dofile("/usr/lib/cclua/net.lua")
  local machine=config.machine()
  local protocol="cclua-apphost-v1"
  local managerProtocol="cclua-manager-v1"
  local managerId=tonumber(machine.manager_computer_id) or 0
  local root="/srv/cclua/apps"
  local running={}

  local function host(path) return tostring(path):gsub("^/","") end
  local function ensure(path)
    path=host(path)
    if path=="" or fs.exists(path) then return end
    local parent=fs.getDir(path)
    if parent~="" and not fs.exists(parent) then ensure(parent) end
    fs.makeDir(path)
  end

  local function app_path(name)
    return root.."/"..tostring(name).."/app.lua"
  end

  local function list_apps()
    ensure(root)
    local out={}
    for _,name in ipairs(fs.list(host(root))) do
      local path=app_path(name)
      if fs.isDir(fs.combine(host(root),name)) and fs.exists(host(path)) then
        local pid=running[name]
        local proc=pid and ctx.kernel.process.get(pid) or nil
        if not proc or proc.state=="exited" or proc.state=="killed" or proc.state=="crashed" then
          running[name]=nil
          pid=nil
        end
        out[#out+1]={name=name,pid=pid,state=pid and "running" or "stopped"}
      end
    end
    table.sort(out,function(a,b)return a.name<b.name end)
    return out
  end

  local function state()
    local s={
      schema=1,
      hostname=machine.hostname,
      computer_id=os.getComputerID(),
      role=machine.role,
      apps=list_apps(),
      timestamp=os.epoch and os.epoch("utc") or 0
    }
    config.write_json("/var/lib/cclua/apphost.json",s)
    return s
  end

  local function start_app(name)
    if running[name] then
      local p=ctx.kernel.process.get(running[name])
      if p and p.state~="exited" and p.state~="killed" and p.state~="crashed" then
        return true,running[name]
      end
      running[name]=nil
    end

    local path=app_path(name)
    if not fs.exists(host(path)) then return nil,"app not installed: "..tostring(name) end

    local proc,err=ctx.kernel.process.create{
      ppid=ctx.process.pid,
      name="app:"..tostring(name),
      uid=0,gid=0,cwd=root.."/"..tostring(name),
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
      if type(mod)=="table" and type(mod.main)=="function" then
        okRun,res=pcall(mod.main,{kernel=ctx.kernel,process=proc,app=name},{})
      elseif type(mod)=="function" then
        okRun,res=pcall(mod,{kernel=ctx.kernel,process=proc,app=name})
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

    reply(sender,{protocol=protocol,op=msg.op,ok=false,error="unknown operation"})
  end

  ensure(root)
  ensure("/var/lib/cclua")
  net.open_management_modems()
  ctx.unit.details={protocol=protocol,manager_id=managerId,root=root}
  ctx.kernel.log.write("info","apphostd","application host online",ctx.unit.details,ctx.process.pid)
  heartbeat()

  local timer=os.startTimer(5)
  while true do
    local ev,a,b,c=coroutine.yield("wait_event")
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
