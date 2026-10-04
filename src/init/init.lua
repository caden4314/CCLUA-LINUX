local k=dofile("/System/kernel/init.lua")

local init,err=k.process.create{
  pid=1,name="init",uid=0,gid=0,cwd="/",
  capabilities=k.capabilities.root(),
  argv={"/sbin/init"}
}
if not init then k.panic.raise(k,"cannot create PID 1",{error=err}) end

local function register_services()
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
  local desktop=machine.role=="desktop-client"
    or tostring(machine.image or ""):find("desktop",1,true)~=nil

  k.log.write("info","init",desktop and "CCLUA Ubuntu Desktop boot" or "CCLUA Ubuntu Server boot",{
    role=machine.role,image=machine.image
  },1)
  print(desktop and "CCLUA Ubuntu 22.04.5 LTS Desktop" or "CCLUA Ubuntu 22.04.5 LTS Server")
  print("Kernel "..k.version.version.." ABI "..k.version.kernel_abi)
  print("Starting services...")

  register_services()
  k.services:start_enabled()

  local session,serr
  if desktop then session,serr=spawn_desktop()
  else session,serr=spawn_console() end

  if not session then
    k.log.write("error","init",desktop and "desktop session spawn failed" or "console spawn failed",{error=serr},1)
    session=select(1,spawn_console())
  end

  local crashStreak=0
  while true do
    local ev,pid=coroutine.yield("wait_event","cclua_process_exit")
    if ev=="cclua_process_exit" and session and pid==session.pid then
      local crashed=session.state=="crashed"
      if crashed then crashStreak=math.min(crashStreak+1,5)
      else crashStreak=0 end

      k.log.write("warning","init",
        desktop and "desktop session exited; restarting" or "console shell exited; restarting",
        {crashed=crashed,crash_streak=crashStreak},1)

      if crashed and k.scheduler and k.scheduler.sleep then
        k.scheduler.sleep(math.min(4,0.5*(2^(crashStreak-1))))
      end

      if desktop then session=select(1,spawn_desktop())
      else session=select(1,spawn_console()) end
    end
  end
end)

k.scheduler:run()
