local M={}

function M.boot(iso,bootInfo)
  local config=ISO.require("system/etc/os.lua")
  local VFS=ISO.require("system/kernel/vfs.lua")
  local Runtime=ISO.require("system/kernel/runtime.lua")
  local Services=ISO.require("system/kernel/services.lua")
  local Display=ISO.require("system/drivers/display.lua")
  local Peripherals=ISO.require("system/drivers/peripherals.lua")
  local BootUI=ISO.require("system/ui/boot.lua")
  local Compositor=ISO.require("system/ui/compositor.lua")
  local WM=ISO.require("system/ui/wm.lua")
  local Packages=ISO.require("system/lib/packages.lua")

  local display=Display.open()
  local vfs=VFS.new(iso,config)

  local ctx={
    iso=iso,config=config,vfs=vfs,display=display,
    bootInfo=bootInfo,apps={},services=nil,runtime=nil,
    compositor=nil,wm=nil,peripherals=nil,
  }

  ctx.peripherals=Peripherals.new(ctx)
  BootUI.run(display,ctx,bootInfo.smoke)

  local compositor=Compositor.new(display)
  local wm=WM.new(compositor)
  ctx.compositor,ctx.wm=compositor,wm
  ctx.packages=Packages.new(ctx)
  if not ctx.packages:findCommand("ssh") and iso.exists("system/packages/lua-ssh.luapkg") then
    local ok,err=ctx.packages:installRaw(iso.read("system/packages/lua-ssh.luapkg"),"system-image")
    if not ok then os.queueEvent("cclua_package_error","lua-ssh",err) end
  end
  ctx.services=Services.new(ctx)
  ctx.runtime=Runtime.new(ctx)

  if os.setComputerLabel then
    os.setComputerLabel(config.name.." "..config.version)
  end

  local serviceModules={
    netd=ISO.require("system/services/netd.lua"),
    server=ISO.require("system/services/ccluanet_server.lua"),
    diagnosticsd=ISO.require("system/services/diagnosticsd.lua"),
    updated=ISO.require("system/services/updated.lua"),
    pkgd=ISO.require("system/services/pkgd.lua"),
    sshd=ISO.require("system/services/sshd.lua"),
    sshclientd=ISO.require("system/services/sshclientd.lua"),
  }

  local role="client"
  local rolePath="/.cclua/data/system/ccluanet.role"
  if fs.exists(rolePath) then
    local h=fs.open(rolePath,"r")
    if h then role=(h.readAll() or "client"):gsub("%s+","");h.close() end
  end
  ctx.networkRole=role

  if role=="server" then
    ctx.services:register("ccluanet-server",function(c)return serviceModules.server.new(c) end,{
      protected=true,critical=true,restartPolicy="on-failure",restartDelay=1,maxRestarts=8,
    })
  else
    ctx.services:register("netd",function(c)return serviceModules.netd.new(c) end,{
      protected=true,critical=false,restartPolicy="on-failure",restartDelay=1,maxRestarts=8,
    })
    local dependentOpts={protected=true,critical=false,depends={"netd"},restartPolicy="on-failure",restartDelay=1,maxRestarts=5}
    ctx.services:register("diagnosticsd",function(c)return serviceModules.diagnosticsd.new(c) end,dependentOpts)
    ctx.services:register("updated",function(c)return serviceModules.updated.new(c) end,dependentOpts)
    ctx.services:register("pkgd",function(c)return serviceModules.pkgd.new(c) end,dependentOpts)
    ctx.services:register("sshd",function(c)return serviceModules.sshd.new(c) end,dependentOpts)
    ctx.services:register("sshclientd",function(c)return serviceModules.sshclientd.new(c) end,dependentOpts)
  end
  ctx.services:startAll()

  ctx.peripherals:onChange(function(event,name,before,after)
    os.queueEvent("cclua_device_change",event,name,before and before.primaryType,after and after.primaryType)
  end)

  local factories={
    terminal=ISO.require("system/apps/terminal.lua"),
    files=ISO.require("system/apps/files.lua"),
    settings=ISO.require("system/apps/settings.lua"),
  }
  for name in pairs(factories) do ctx.apps[name]=true end

  local appCapabilities={
    terminal={"fs.user.*","fs.appdata.*","fs.temp.*","fs.system.read","fs.virtual.read","proc.signal"},
    files={"fs.user.*","fs.appdata.read","fs.temp.read","fs.system.read","fs.virtual.read"},
    settings={"fs.user.read","fs.system.read","fs.virtual.read"},
  }

  local cascade=0
  function ctx.openApp(name)
    local factory=factories[name]
    if not factory then return nil,"unknown app" end
    local app,originalEvent,originalClose
    local pid,perr=ctx.runtime:spawnProcess("app:"..name,function(processCtx)
      app=factory.new(processCtx)
      originalEvent=app.event
      originalClose=app.close
      while true do
        local _,action,args=os.pullEventRaw("cclua_app_event")
        if action=="event" then
          if originalEvent then originalEvent(table.unpack(args or {})) end
        elseif action=="close" then
          if originalClose then pcall(originalClose) end
          return true
        end
      end
    end,{
      kind="app",session="desktop",user=config.user.name,
      capabilities=appCapabilities[name] or {"fs.user.read","fs.system.read","fs.virtual.read"},
      pty=name=="terminal" and {cols=51,rows=19} or false,
    })
    if not pid or not app then return nil,perr or "application process failed to initialize" end

    cascade=(cascade+1)%6
    local widths={terminal=48,files=42,settings=44}
    local heights={terminal=18,files=17,settings=18}
    local titles={terminal="Terminal",files="Files",settings="Settings"}
    local win=compositor:createWindow({
      title=titles[name] or name,
      width=math.min(widths[name] or 40,compositor.width-2),
      height=math.min(heights[name] or 14,compositor.height-3),
      x=3+cascade*2,y=3+cascade,
    })
    app.processPid=pid
    app.event=function(...)
      return ctx.processes:send(pid,"cclua_app_event","event",{...})
    end
    app.close=function()
      local proc=ctx.processes:get(pid)
      if proc and proc.state~="exited" and proc.state~="crashed" and proc.state~="killed" then
        ctx.processes:send(pid,"cclua_app_event","close",{})
      end
    end
    wm:attach(win,app)
    compositor:raise(win.id)
    compositor:present()
    return win
  end

  local desktopFactory=ISO.require("system/apps/desktop.lua")
  local desktop=desktopFactory.new(ctx)
  wm:setDesktopHandler(desktop)
  desktop.start()

  if not vfs.exists(config.user.home.."/Welcome.txt") then
    vfs.write(config.user.home.."/Welcome.txt",
      "Welcome to "..config.name.." "..config.version.."\n"..
      "System image: "..tostring(iso.meta.version or "?").."\n",false)
  end
  vfs.mkdir("/AppData/terminal")
  vfs.mkdir("/AppData/files")
  vfs.mkdir("/AppData/settings")

  ctx.openApp("terminal")
  compositor:present(true)

  if bootInfo.smoke then
    local probePid,probeErr=ctx.runtime:spawn("smoke-scheduler",function()
      local event,value=os.pullEventRaw("cclua_scheduler_probe")
      if event~="cclua_scheduler_probe" or value~="ok" then
        error("scheduler probe received invalid event")
      end
      return "pass"
    end)
    if not probePid then error("scheduler probe spawn failed: "..tostring(probeErr),0) end
    local probeDispatch,probeDispatchErr=ctx.runtime:dispatch("cclua_scheduler_probe","ok")
    if not probeDispatch then error("scheduler probe dispatch failed: "..tostring(probeDispatchErr),0) end
    local probe=ctx.scheduler:get(probePid)
    if not probe or probe.state~="exited" or probe.result~="pass" then
      error("scheduler probe did not exit cleanly",0)
    end

    local terminalProc
    for _,proc in ipairs(ctx.processes:list(false)) do
      if proc.name=="app:terminal" then terminalProc=proc;break end
    end
    if not terminalProc or terminalProc.session~="desktop" or not terminalProc.pty then
      error("terminal process/session/pty was not initialized",0)
    end
    if not ctx.processes:has(terminalProc.pid,"fs.user.read") or
       ctx.processes:has(terminalProc.pid,"fs.system.write") then
      error("terminal capability set is invalid",0)
    end
    local deniedWrite,deniedErr=ctx.processes:context(terminalProc.pid).vfs.write("/System/.process-smoke","forbidden",false)
    if deniedWrite or not tostring(deniedErr):find("capability denied",1,true) then
      error("process VFS capability guard failed",0)
    end

    local processPid,processErr=ctx.runtime:spawnProcess("smoke-process",function(processCtx)
      if not processCtx.pty then error("smoke process has no pty") end
      processCtx.pty:write("process-online")
      local _,action,value=os.pullEventRaw("cclua_process_probe")
      if action~="reply" then error("targeted process message mismatch") end
      return value
    end,{kind="test",session="smoke",capabilities={"fs.user.read"},pty=true})
    if not processPid then error("process spawn failed: "..tostring(processErr),0) end
    local sent,sendErr=ctx.processes:send(processPid,"cclua_process_probe","reply","pass")
    if not sent then error("process targeted send failed: "..tostring(sendErr),0) end
    local processProbe=ctx.processes:get(processPid)
    if not processProbe or processProbe.state~="exited" or processProbe.pty:peek()~="process-online" then
      error("process/pty probe did not exit cleanly",0)
    end

    local serviceProbe=ctx.services:snapshot()
    for _,name in ipairs({"diagnosticsd","updated","pkgd","sshd","sshclientd"}) do
      local svc=serviceProbe[name]
      if not svc or svc.depends[1]~="netd" or svc.restartPolicy~="on-failure" then
        error("service dependency/restart policy invalid: "..name,0)
      end
    end

    if not ctx.packages:findCommand("ssh") then
      error("bundled lua-ssh package was not installed",0)
    end
    local badName="CCLUAPKG/1\nMETA name=../escape\nMETA version=1\nMETA architecture=cclua32\n"
    local badNameRec=ctx.packages:installRaw(badName,"smoke")
    if badNameRec then error("unsafe package name was accepted",0) end
    local badCommand="CCLUAPKG/1\nMETA name=smoke-guard\nMETA version=1\nMETA architecture=cclua32\nMETA commands=x:../../escape.lua\n"
    local badCommandRec=ctx.packages:installRaw(badCommand,"smoke")
    if badCommandRec then error("unsafe package command path was accepted",0) end
    local badArch="CCLUAPKG/1\nMETA name=smoke-arch\nMETA version=1\nMETA architecture=wrongarch\n"
    local badArchRec=ctx.packages:installRaw(badArch,"smoke")
    if badArchRec then error("foreign package architecture was accepted",0) end

    local userProbe=config.user.home.."/.cclua-smoke"
    local homeProbe="/home/"..config.user.name.."/.cclua-smoke"
    local wok,werr=vfs.write(userProbe,"user-data",false)
    if not wok then error("user VFS write failed: "..tostring(werr),0) end
    local aliasData=vfs.read(homeProbe)
    if aliasData~="user-data" then error("/home alias did not resolve user data",0) end
    local appOk,appErr=vfs.write("/AppData/smoke/state","app-data",false)
    if not appOk then error("AppData VFS write failed: "..tostring(appErr),0) end
    local tempOk,tempErr=vfs.write("/Temp/smoke.tmp","temp-data",false)
    if not tempOk then error("Temp VFS write failed: "..tostring(tempErr),0) end
    local sysOk,sysErr=vfs.write("/System/.cclua-smoke","forbidden",false)
    if sysOk or sysErr~="read-only filesystem" then error("/System write guard failed",0) end

    local rows=compositor:compose()
    local h=fs.open("/.cclua/smoke-frame.tsv","w")
    if h then
      for y,row in ipairs(rows) do
        h.write(row[1].."\t"..row[2].."\t"..row[3].."\n")
      end
      h.close()
    end
    local d=fs.open("/.cclua/smoke-result.txt","w")
    if d then
      d.write("CCLUA_LINUX_SMOKE_PASS\n")
      d.write("version="..config.version.."\n")
      d.write("display="..compositor.width.."x"..compositor.height.."\n")
      d.write("iso_files="..tostring(iso.meta.files or "?").."\n")
      local sched=ctx.scheduler:status()
      d.write("scheduler.probe=pass\n")
      d.write("scheduler.created="..tostring(sched.totalCreated or 0).."\n")
      d.write("scheduler.resumes="..tostring(sched.totalResumes or 0).."\n")
      d.write("scheduler.crashes="..tostring(sched.crashes or 0).."\n")
      local procStatus=ctx.processes:status()
      d.write("process.terminal=pass\n")
      d.write("process.pty=pass\n")
      d.write("process.capabilities=pass\n")
      d.write("process.created="..tostring(procStatus.created or 0).."\n")
      d.write("service.dependencies=pass\n")
      d.write("package.lua-ssh=pass\n")
      d.write("package.guard=pass\n")
      d.write("vfs.home-alias=pass\n")
      d.write("vfs.system-readonly=pass\n")
      d.write("vfs.mutable-roots=pass\n")
      local snap=ctx.services:snapshot()
      for name,state in pairs(snap) do
        d.write("service."..name.."="..state.state.."\n")
        if state.lastError then
          local cleanErr=tostring(state.lastError):gsub("[\r\n]+"," ")
          d.write("service."..name..".error="..cleanErr.."\n")
        end
      end
      d.close()
    end
    if os.shutdown then os.shutdown() end
    return true
  end

  local ok,err=xpcall(function() return ctx.runtime:run() end,debug.traceback)
  display:cursor(1,1,false,colors.white)
  if not ok then
    display:clear()
    printError("CCLUA-LINUX kernel panic")
    printError(err)
  end
  return ok,err
end

return M
