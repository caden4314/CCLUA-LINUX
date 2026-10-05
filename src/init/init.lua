local k=dofile("/System/kernel/init.lua")

local init,err=k.process.create{
  pid=1,name="init",uid=0,gid=0,cwd="/",
  capabilities=k.capabilities.root(),
  argv={"/sbin/init"}
}
if not init then k.panic.raise(k,"cannot create PID 1",{error=err}) end

local function register_services(recoveryMode)
  local imported=k.services:load_ubuntu_reference()
  k.log.write("info","init","imported Ubuntu systemd unit metadata",{units=imported},1)

  local function load_service(path)
    local ok,fn=pcall(dofile,path)
    if not ok then error(fn,0) end
    return fn
  end

  k.services:register{
    name="systemd-journald.service",
    description="CCLUA journal service",
    enabled=true,
    exec=load_service("/usr/lib/cclua/services/journald.lua")
  }
  k.services:register{
    name="systemd-networkd.service",
    description="Network Service",
    enabled=true,
    exec=load_service("/usr/lib/cclua/services/netd.lua")
  }
  k.services:register{
    name="systemd-resolved.service",
    description="Network Name Resolution",
    enabled=true,
    exec=load_service("/usr/lib/cclua/services/resolved.lua")
  }
  k.services:register{
    name="cron.service",
    description="CCLUA periodic scheduler",
    enabled=true,
    exec=load_service("/usr/lib/cclua/services/crond.lua")
  }
  k.services:register{
    name="peripherald.service",
    description="CCLUA peripheral inventory and hotplug monitor",
    enabled=true,
    exec=load_service("/usr/lib/cclua/services/peripherald.lua")
  }
  k.services:register{
    name="cclua-statusd.service",
    description="CCLUA system health and chassis status lamp",
    enabled=true,
    exec=load_service("/usr/lib/cclua/services/statusd.lua")
  }
  k.services:register{
    name="cclua-controld.service",
    description="CCLUA authenticated fleet node control service",
    enabled=true,
    exec=load_service("/usr/lib/cclua/services/controld.lua")
  }

  -- Fatal POST failures must still be able to reach a diagnostic shell. Do
  -- not load optional/role-specific units which may be the thing POST found
  -- missing or corrupt.
  if recoveryMode then return end

  local config=dofile("/usr/lib/cclua/config.lua")
  local machine=config.machine()
  local managerRole=machine.role=="manager" or machine.role=="network-manager"

  if managerRole then
    k.services:register{
      name="cclua-managerd.service",
      description="CCLUA GitHub image and fleet network manager",
      enabled=true,
      exec=load_service("/usr/lib/cclua/services/managerd.lua")
    }
  else
    k.services:register{
      name="cclua-update-agent.service",
      description="CCLUA manager discovery and update status agent",
      enabled=true,
      exec=load_service("/usr/lib/cclua/services/update-agent.lua")
    }
  end

  if machine.role=="lighting-controller" then
    k.services:register{
      name="cclua-lightingd.service",
      description="CCLUA wired redstone lighting controller",
      enabled=true,
      exec=load_service("/usr/lib/cclua/services/lightingd.lua")
    }
  elseif machine.role=="app-server" then
    k.services:register{
      name="cclua-apphostd.service",
      description="CCLUA managed application host",
      enabled=true,
      exec=load_service("/usr/lib/cclua/services/apphostd.lua")
    }
  elseif machine.role=="fleet-monitor" then
    k.services:register{
      name="cclua-server-room-monitor.service",
      description="CCLUA Server Room fleet dashboard",
      enabled=true,
      exec=load_service("/usr/lib/cclua/services/server-room-monitor.lua")
    }
  elseif machine.role=="gps-control" then
    k.services:register{
      name="cclua-gps-control.service",
      description="CCLUA GPS control service",
      enabled=true,
      exec=load_service("/usr/lib/cclua/services/gps-control.lua")
    }
  elseif machine.role=="gps-monitor" then
    k.services:register{
      name="cclua-gps-monitor.service",
      description="CCLUA GPS operations wall monitor",
      enabled=true,
      exec=load_service("/usr/lib/cclua/services/gps-monitor.lua")
    }
  elseif machine.role=="gps-host" then
    k.services:register{
      name="cclua-gps-host.service",
      description="CCLUA GPS positioning host",
      enabled=true,
      exec=load_service("/usr/lib/cclua/services/gps-host.lua")
    }
  elseif machine.role=="theater-controller" or machine.theater_enabled==true then
    k.services:register{
      name="cclua-theaterd.service",
      description="CCLUA cinema displays, audio and lighting controller",
      enabled=true,
      exec=load_service("/usr/lib/cclua/services/theaterd.lua")
    }
  end

  if machine.dashboard_enabled~=false then
    k.services:register{
      name="dashboard.service",
      description="CCLUA monitor statistics dashboard",
      enabled=true,
      exec=load_service("/usr/lib/cclua/services/dashboard.lua")
    }
  end
end

local function spawn_console()
  local p,perr=k.process.create{
    ppid=1,name="bash",uid=0,gid=0,cwd="/root",
    capabilities=k.capabilities.root(),
    argv={"/usr/bin/bash.lua","--login"},
    session_id=1,process_group=1
  }
  if not p then return nil,perr end
  k.scheduler:add(p,function()
    local mod=dofile("/usr/bin/bash.lua")
    return mod.main({kernel=k,process=p},{"--login"})
  end)
  return p
end

local function spawn_desktop()
  local user=k.users.by_name("caden")
  if not user then return nil,"desktop user caden is missing" end
  local groups={}
  for _,g in ipairs(k.users.groups_for(user)) do groups[#groups+1]=g.gid end

  local p,perr=k.process.create{
    ppid=1,name="gnome-shell",uid=user.uid,gid=user.gid,groups=groups,
    cwd=user.home or "/home/caden",
    capabilities={},
    environment={
      HOME=user.home or "/home/caden",
      USER=user.name,
      LOGNAME=user.name,
      SHELL=user.shell or "/usr/bin/bash.lua",
      PATH="/usr/bin:/usr/sbin:/bin:/sbin",
      DESKTOP_SESSION="ubuntu",
      XDG_SESSION_TYPE="cclua",
      XDG_CURRENT_DESKTOP="ubuntu:GNOME",
      XDG_SESSION_DESKTOP="ubuntu",
    },
    argv={"/usr/bin/cclua-desktop.lua","--session"},
    session_id=1,process_group=1
  }
  if not p then return nil,perr end
  k.scheduler:add(p,function()
    local mod=dofile("/usr/bin/cclua-desktop.lua")
    return mod.main({kernel=k,process=p},{"--session"})
  end)
  return p
end

k.scheduler:add(init,function()
  local config=dofile("/usr/lib/cclua/config.lua")
  local machine=config.machine()
  local wantsDesktop=machine.role=="desktop-client"
    or machine.role=="theater-controller"
    or tostring(machine.image or ""):find("desktop",1,true)~=nil
  local desktop=wantsDesktop

  k.log.write("info","init",desktop and "CCLUA Ubuntu Desktop boot" or "CCLUA Ubuntu Server boot",{
    role=machine.role,image=machine.image
  },1)

  -- POST runs after the kernel is mounted/scheduled but before any role
  -- services start. This gives us a real boot gate instead of discovering a
  -- broken image after the service fleet has already started.
  local postResult
  do
    local ok,postOrErr=pcall(function()
      return dofile("/usr/lib/cclua/post.lua").run(
        {kernel=k,process=init},
        {animate=true,monitors=true}
      )
    end)
    if ok and type(postOrErr)=="table" then
      postResult=postOrErr
    else
      postResult={
        state="FAILED",fatal=true,degraded=true,
        pass=0,warn=0,fail=1,fatal_count=1,
        checks={{id="post-engine",label="POST engine",state="FAIL",critical=true,detail=tostring(postOrErr)}}
      }
      k.log.write("critical","init","POST engine failed",{error=tostring(postOrErr)},1)
    end
  end

  local recovery=postResult.fatal==true
  register_services(recovery)

  if recovery then
    desktop=false
    term.setTextColor(colors.red)
    print("Entering CCLUA recovery mode: fatal POST failure.")
    term.setTextColor(colors.white)

    -- Keep only the minimum diagnostic/control plane online. Role services,
    -- dashboards and update activation are intentionally held back until an
    -- operator can inspect the failure.
    local safe={
      "systemd-journald.service",
      "systemd-networkd.service",
      "systemd-resolved.service",
      "peripherald.service",
      "cclua-statusd.service",
      "cclua-controld.service",
    }
    for _,name in ipairs(safe) do
      local ok,err=k.services:start(name)
      if not ok then k.log.write("error","init","recovery service failed to start",{unit=name,error=err},1) end
    end
  else
    print("Starting CCLUA services...")
    k.services:start_enabled()
  end

  local function write_session_state(mode,session,crashStreak,lastError)
    config.write_json("/var/lib/cclua/session-health.json",{
      schema=1,
      mode=mode,
      desired=wantsDesktop and "desktop" or "console",
      recovery=recovery,
      pid=session and session.pid or nil,
      state=session and session.state or "missing",
      crash_streak=crashStreak or 0,
      last_error=lastError,
      timestamp=os.epoch and os.epoch("utc") or 0,
    })
  end

  local session,serr
  if desktop then session,serr=spawn_desktop()
  else session,serr=spawn_console() end

  if not session and desktop then
    k.log.write("error","init","desktop session spawn failed; falling back to recovery console",{error=serr},1)
    desktop=false
    recovery=true
    session,serr=spawn_console()
  elseif not session then
    k.log.write("critical","init","console spawn failed",{error=serr},1)
  end

  if not session then
    k.panic.raise(k,"unable to start an interactive session",{error=serr,recovery=recovery})
  end

  local crashStreak=0
  write_session_state(desktop and "desktop" or "console",session,crashStreak,nil)

  while true do
    local ev,pid,exitCode,exitState=coroutine.yield("wait_event","cclua_process_exit")
    if ev=="cclua_process_exit" and session and pid==session.pid then
      local crashed=session.state=="crashed" or exitState=="crashed"
      local lastError=session.error or session.traceback
      if crashed then crashStreak=math.min(crashStreak+1,8)
      else crashStreak=0 end

      k.log.write(crashed and "error" or "warning","init",
        desktop and "desktop session exited; restarting" or "console shell exited; restarting",
        {
          crashed=crashed,crash_streak=crashStreak,exit_code=exitCode,
          error=lastError,mode=desktop and "desktop" or "console"
        },1)

      -- A desktop which crashes repeatedly is more useful as a working
      -- recovery console than as an endless compositor restart loop.
      if desktop and crashed and crashStreak>=3 then
        k.log.write("critical","init","desktop crash loop; switching to recovery console",{
          crash_streak=crashStreak,error=lastError
        },1)
        desktop=false
        recovery=true
        crashStreak=0
      end

      if crashed and k.scheduler and k.scheduler.sleep then
        k.scheduler.sleep(math.min(8,0.5*(2^math.max(0,crashStreak-1))))
      end

      local nextSession,nextErr
      if desktop then nextSession,nextErr=spawn_desktop()
      else nextSession,nextErr=spawn_console() end
      session=nextSession

      if not session then
        k.log.write("critical","init","session restart failed",{error=nextErr,mode=desktop and "desktop" or "console"},1)
        if desktop then
          desktop=false
          recovery=true
          session,nextErr=spawn_console()
        end
      end

      if not session then
        k.panic.raise(k,"interactive session restart failed",{error=nextErr})
      end
      write_session_state(desktop and "desktop" or "console",session,crashStreak,lastError)
    end
  end
end)

k.scheduler:run()
