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
    name="dashboard.service",
    description="CCLUA monitor statistics dashboard",
    enabled=true,
    exec=load_service("/usr/lib/cclua/services/dashboard.lua")
  }
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

k.scheduler:add(init,function()
  k.log.write("info","init","CCLUA Ubuntu Server boot",nil,1)
  print("CCLUA Ubuntu 22.04.5 LTS Server")
  print("Kernel "..k.version.version.." ABI "..k.version.kernel_abi)
  print("Starting services...")

  register_services()
  k.services:start_enabled()

  local console,cerr=spawn_console()
  if not console then k.log.write("error","init","console spawn failed",{error=cerr},1) end

  while true do
    local ev,pid=coroutine.yield("wait_event","cclua_process_exit")
    if ev=="cclua_process_exit" and console and pid==console.pid then
      k.log.write("warning","init","console shell exited; restarting",nil,1)
      console=select(1,spawn_console())
    end
  end
end)

k.scheduler:run()
