return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local machine=config.machine()
  local side=machine.status_light_side or "bottom"
  local enabled=machine.status_light_enabled~=false
  local valid={top=true,bottom=true,left=true,right=true,front=true,back=true}

  if not valid[side] then
    ctx.kernel.log.write("warning","statusd","invalid status light side; using bottom",{configured=side},ctx.process.pid)
    side="bottom"
  end

  local function update_state()
    return config.read_json("/var/lib/cclua/update-state.json",{})
  end

  local function failed_services()
    local out={}
    for _,u in ipairs(ctx.kernel.services:list()) do
      if u.state=="failed" then out[#out+1]=u.name end
    end
    return out
  end

  local function active_service(name)
    local u=ctx.kernel.services:get(name)
    return u and u.state=="active"
  end

  local function classify()
    local failed=failed_services()
    local update=update_state()
    local phase=tostring(update.state or update.phase or ""):upper()

    if #failed>0 or phase=="DEGRADED" or phase=="ROLLBACK" or phase=="FAILED" then
      return "DEGRADED",failed,update
    end

    local updating={
      CHECKING=true,DOWNLOADING=true,VERIFYING=true,STAGING=true,
      READY=true,ACTIVATING=true,HEALTH_CHECK=true
    }
    if updating[phase] then return "UPDATING",failed,update end

    if os.clock()<4
      or not active_service("systemd-networkd.service")
      or not active_service("peripherald.service") then
      return "BOOTING",failed,update
    end

    return "HEALTHY",failed,update
  end

  local function lamp(state,tick)
    if not enabled then return false end
    if state=="HEALTHY" then return true end
    if state=="DEGRADED" then return tick%2==0 end
    if state=="UPDATING" then return math.floor(tick/2)%2==0 end
    return math.floor(tick/3)%2==0
  end

  local previous=nil
  local tick=0
  local timer=os.startTimer(0.15)

  while true do
    local ev,a=coroutine.yield("wait_event")
    if ev=="timer" and a==timer then
      tick=tick+1
      local state,failed,update=classify()
      local output=lamp(state,tick)
      pcall(redstone.setOutput,side,output)

      if state~=previous or tick%20==0 then
        config.write_json("/var/lib/cclua/status.json",{
          schema=1,
          state=state,
          healthy=state=="HEALTHY",
          computer_id=os.getComputerID(),
          hostname=machine.hostname,
          role=machine.role,
          lamp_side=side,
          lamp_output=output,
          failed_services=failed,
          update=update,
          timestamp=os.epoch and os.epoch("utc") or 0
        })
      end

      if state~=previous then
        ctx.kernel.log.write(
          state=="DEGRADED" and "error" or "info",
          "statusd",
          "system status "..state,
          {lamp_side=side,failed_services=failed},
          ctx.process.pid
        )
        previous=state
      end

      local delay=state=="DEGRADED" and 0.15 or 0.25
      timer=os.startTimer(delay)
    elseif ev=="terminate" then
      pcall(redstone.setOutput,side,false)
      return 0
    end
  end
end
