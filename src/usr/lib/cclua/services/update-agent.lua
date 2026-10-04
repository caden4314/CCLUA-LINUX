return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local machine=config.machine()
  local protocol="cclua-manager-v1"
  local managerId=nil
  local lastManager=nil

  local function open_modems()
    local opened=0
    for _,name in ipairs(peripheral.getNames()) do
      if peripheral.hasType(name,"modem") then
        local ok=pcall(rednet.open,name)
        if ok then opened=opened+1 end
      end
    end
    return opened
  end

  local function read_text(path)
    path=tostring(path):gsub("^/","")
    if not fs.exists(path) then return nil end
    local h=fs.open(path,"r")
    if not h then return nil end
    local v=h.readAll()
    h.close()
    return v and v:gsub("%s+$","") or nil
  end

  local function local_commit()
    return read_text("/var/lib/cclua/installed-commit")
      or machine.image_commit
      or machine.build_commit
      or "unknown"
  end

  local function write_state(state,extra)
    local payload={
      schema=1,
      state=state,
      current_commit=local_commit(),
      manager_id=managerId,
      manager_commit=lastManager and lastManager.commit or nil,
      manager_ref=lastManager and lastManager.ref or nil,
      checked_at=os.epoch and os.epoch("utc") or 0,
    }
    for k,v in pairs(extra or {}) do payload[k]=v end
    config.write_json("/var/lib/cclua/update-state.json",payload)
  end

  local function request_status()
    write_state("CHECKING")
    local status=config.read_json("/var/lib/cclua/status.json",{})
    rednet.broadcast({
      protocol=protocol,
      op="status",
      hostname=machine.hostname,
      role=machine.role,
      status={
        hostname=machine.hostname,
        role=machine.role,
        system_state=status.state,
        current_commit=local_commit(),
        processes=#ctx.kernel.process.all(),
        services=(function()
          local n=0
          for _,u in ipairs(ctx.kernel.services:list()) do
            if u.state=="active" then n=n+1 end
          end
          return n
        end)(),
        peripherals=(function()
          local n=0
          for _ in pairs(ctx.kernel.device.devices or {}) do n=n+1 end
          return n
        end)()
      }
    },protocol)
  end

  local opened=open_modems()
  ctx.unit.details={protocol=protocol,modems=opened}
  ctx.kernel.log.write("info","update-agent","manager update agent online",{modems=opened},ctx.process.pid)

  write_state("CHECKING")
  request_status()

  local poll=os.startTimer(15)
  local timeout=os.startTimer(3)

  while true do
    local ev,a,b,c=coroutine.yield("wait_event")
    if ev=="timer" and a==poll then
      request_status()
      timeout=os.startTimer(3)
      poll=os.startTimer(15)

    elseif ev=="timer" and a==timeout then
      if not lastManager then
        write_state("OFFLINE",{error="manager not discovered"})
      end

    elseif ev=="rednet_message" and c==protocol then
      local sender,msg=a,b
      if type(msg)=="table" and msg.protocol==protocol and msg.op=="status" and msg.ok and type(msg.status)=="table" then
        managerId=sender
        lastManager=msg.status

        local current=local_commit()
        local available=tostring(lastManager.commit or "unknown")
        local state
        if current=="unknown" then
          state="UNTRACKED"
        elseif available=="unknown" or available=="-" then
          state="UNKNOWN"
        elseif current==available then
          state="CURRENT"
        else
          state="AVAILABLE"
        end

        write_state(state,{
          available_commit=available,
          active_slot=lastManager.activeSlot,
          manager_state=lastManager.managerState,
          manager_error=lastManager.lastError,
        })
      end

    elseif ev=="peripheral" then
      opened=open_modems()
      ctx.unit.details.modems=opened
    end
  end
end
