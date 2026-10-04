return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local machine=config.machine()
  local side=machine.status_light_side or "bottom"
  local enabled=machine.status_light_enabled~=false
  local valid={top=true,bottom=true,left=true,right=true,front=true,back=true}

  local function refresh_light_config()
    local fresh=config.machine()
    local nextSide=fresh.status_light_side or "bottom"
    if not valid[nextSide] then
      ctx.kernel.log.write("warning","statusd","invalid status light side; using bottom",{configured=nextSide},ctx.process.pid)
      nextSide="bottom"
    end
    if nextSide~=side then
      pcall(redstone.setOutput,side,false)
      ctx.kernel.log.write("info","statusd","status light moved",{old_side=side,new_side=nextSide},ctx.process.pid)
      side=nextSide
    end
    enabled=fresh.status_light_enabled~=false
    machine=fresh
  end

  refresh_light_config()

  local function update_state()
    return config.read_json("/var/lib/cclua/update-state.json",{})
  end

  local function failed_services()
    local out={}
    for _,u in ipairs(ctx.kernel.services:list()) do
      if u.state=="failed" then out[#out+1]={name=u.name,error=u.error} end
    end
    return out
  end

  local function failed_names(failed)
    local out={}
    for _,u in ipairs(failed or {}) do out[#out+1]=u.name end
    return out
  end

  local function active_service(name)
    local u=ctx.kernel.services:get(name)
    return u and u.state=="active"
  end

  local function role_fault()
    if machine.role=="lighting-controller" then
      local lighting=config.read_json("/var/lib/cclua/lighting.json",{})
      if lighting.healthy==false then
        local reason=lighting.error
        if not reason and #(lighting.missing_relays or {})>0 then
          reason="missing relays: "..table.concat(lighting.missing_relays,",")
        end
        return true,reason or "lighting hardware fault"
      end
    end
    return false,nil
  end

  local function classify()
    local failed=failed_services()
    local update=update_state()
    local phase=tostring(update.state or update.phase or ""):upper()

    if #failed>0 then
      return "DEGRADED",1,"service failure",failed,update
    end

    if phase=="FAILED" or phase=="ROLLBACK" then
      return "DEGRADED",2,"update/rollback failure",failed,update
    end

    if phase=="OFFLINE" or phase=="DEGRADED"
      or tostring(update.manager_state or ""):upper()=="DEGRADED" then
      return "DEGRADED",3,"manager/network fault",failed,update
    end

    local badRole,roleReason=role_fault()
    if badRole then
      return "DEGRADED",4,roleReason,failed,update
    end

    local updating={
      CHECKING=true,DOWNLOADING=true,VERIFYING=true,STAGING=true,
      READY=true,ACTIVATING=true,HEALTH_CHECK=true,AVAILABLE=true
    }
    if updating[phase] then return "UPDATING",0,nil,failed,update end

    if os.clock()<4
      or not active_service("systemd-networkd.service")
      or not active_service("peripherald.service") then
      return "BOOTING",0,nil,failed,update
    end

    return "HEALTHY",0,nil,failed,update
  end

  local function lamp(code,tick)
    if not enabled or not code or code<=0 then return false end
    -- Each code is N short pulses followed by a clear pause.
    -- 150 ms scheduler tick: 300 ms ON, 300 ms OFF, then ~1.5 s gap.
    local pulseTicks=4
    local gapTicks=10
    local cycle=code*pulseTicks+gapTicks
    local phase=tick%cycle
    if phase>=code*pulseTicks then return false end
    return (phase%pulseTicks)<2
  end

  local previous=nil
  local previousCode=nil
  local tick=0
  local timer=os.startTimer(0.15)

  while true do
    local ev,a=coroutine.yield("wait_event")
    if ev=="timer" and a==timer then
      tick=tick+1
      if tick%20==1 then refresh_light_config() end

      local state,errorCode,errorReason,failed,update=classify()
      local output=lamp(errorCode,tick)
      pcall(redstone.setOutput,side,output)

      if state~=previous or errorCode~=previousCode or tick%20==0 then
        local payload={
          schema=2,
          state=state,
          healthy=state=="HEALTHY",
          computer_id=os.getComputerID(),
          hostname=machine.hostname,
          role=machine.role,
          lamp_side=side,
          lamp_output=output,
          lamp_mode=errorCode>0 and "FAULT_CODE" or "OFF",
          error_code=errorCode,
          error_reason=errorReason,
          failed_services=failed_names(failed),
          failed_units=failed,
          update=update,
          timestamp=os.epoch and os.epoch("utc") or 0
        }
        config.write_json("/var/lib/cclua/status.json",payload)
        config.write_json("/var/log/cclua/health.json",payload)
      end

      if state~=previous or errorCode~=previousCode then
        ctx.kernel.log.write(
          errorCode>0 and "error" or "info",
          "statusd",
          errorCode>0
            and ("system fault code "..tostring(errorCode)..": "..tostring(errorReason))
            or ("system status "..state),
          {
            lamp_side=side,error_code=errorCode,error_reason=errorReason,
            failed_services=failed_names(failed),failed_units=failed
          },
          ctx.process.pid
        )
        previous=state
        previousCode=errorCode
      end

      timer=os.startTimer(0.15)
    elseif ev=="terminate" then
      pcall(redstone.setOutput,side,false)
      return 0
    end
  end
end
