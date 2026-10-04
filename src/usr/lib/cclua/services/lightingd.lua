return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local net=dofile("/usr/lib/cclua/net.lua")
  local machine=config.machine()
  local protocol="cclua-lighting-v1"
  local managerProtocol="cclua-manager-v1"
  local managerId=tonumber(machine.manager_computer_id) or 0
  local settings=config.read_json("/etc/cclua/lighting.json",{})
  local sides={"top","bottom","left","right","front","back"}
  local relays={}
  local desired=settings.default_on~=false
  local lastError=nil

  local function relay_id(name)
    return tonumber(tostring(name):match("_(%d+)$")) or 99999
  end

  local function discover()
    local found={}
    for _,name in ipairs(peripheral.getNames()) do
      if peripheral.hasType(name,"redstone_relay") then
        found[#found+1]=name
      end
    end
    table.sort(found,function(a,b)
      local ai,bi=relay_id(a),relay_id(b)
      if ai==bi then return a<b end
      return ai<bi
    end)
    relays=found
    return found
  end

  local function set_relay(name,value,side)
    if not peripheral.hasType(name,"redstone_relay") then
      return nil,"relay not present: "..tostring(name)
    end
    local relay=peripheral.wrap(name)
    if not relay or type(relay.setOutput)~="function" then
      return nil,"relay has no setOutput: "..tostring(name)
    end

    if side then
      local ok,err=pcall(relay.setOutput,side,value==true)
      if not ok then return nil,tostring(err) end
    else
      for _,s in ipairs(sides) do
        local ok,err=pcall(relay.setOutput,s,value==true)
        if not ok then return nil,tostring(err) end
      end
    end
    return true
  end

  local function set_all(value)
    discover()
    local errors={}
    for _,name in ipairs(relays) do
      local ok,err=set_relay(name,value)
      if not ok then errors[#errors+1]=name..": "..tostring(err) end
    end
    desired=value==true
    lastError=#errors>0 and table.concat(errors,"; ") or nil
    return #errors==0,lastError
  end

  local function relay_state(name)
    local relay=peripheral.wrap(name)
    local outputs={}
    if relay and type(relay.getOutput)=="function" then
      for _,side in ipairs(sides) do
        local ok,v=pcall(relay.getOutput,side)
        if ok then outputs[side]=v==true end
      end
    end
    return {name=name,id=relay_id(name),outputs=outputs}
  end

  local function snapshot()
    discover()
    local items={}
    for _,name in ipairs(relays) do items[#items+1]=relay_state(name) end
    local expected=settings.expected_relays or {}
    local present={}
    for _,name in ipairs(relays) do present[name]=true end
    local missing={}
    for _,name in ipairs(expected) do
      if not present[name] then missing[#missing+1]=name end
    end
    local state={
      schema=1,
      hostname=machine.hostname,
      computer_id=os.getComputerID(),
      role=machine.role,
      desired_on=desired,
      relay_count=#relays,
      relays=items,
      expected_relays=expected,
      missing_relays=missing,
      healthy=(#relays>0 and #missing==0 and lastError==nil),
      error=lastError,
      timestamp=os.epoch and os.epoch("utc") or 0
    }
    config.write_json("/var/lib/cclua/lighting.json",state)
    config.write_json("/var/log/cclua/lighting-health.json",state)
    return state
  end

  local function heartbeat()
    local state=snapshot()
    rednet.send(managerId,{
      protocol=managerProtocol,
      op="status",
      hostname=machine.hostname,
      role=machine.role,
      status={
        hostname=machine.hostname,
        role=machine.role,
        system_state=state.healthy and "HEALTHY" or "DEGRADED",
        lighting=state,
        relays=state.relay_count,
        processes=#ctx.kernel.process.all(),
        services=(function()
          local n=0
          for _,u in ipairs(ctx.kernel.services:list()) do
            if u.state=="active" then n=n+1 end
          end
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
      ctx.kernel.log.write("warning","lightingd","rejected lighting command from unauthorized sender",{sender=sender},ctx.process.pid)
      return
    end
    if type(msg)~="table" or msg.protocol~=protocol then return end

    if msg.op=="status" or msg.op=="discover" then
      reply(sender,{protocol=protocol,op=msg.op,ok=true,state=snapshot()})
      return
    end

    if msg.op=="all" then
      local ok,err=set_all(msg.value==true)
      local state=snapshot()
      ctx.kernel.log.write(ok and "info" or "error","lightingd","all lights "..(msg.value and "on" or "off"),{
        sender=sender,relay_count=#relays,error=err
      },ctx.process.pid)
      reply(sender,{protocol=protocol,op="all",ok=ok,error=err,state=state})
      return
    end

    if msg.op=="set" then
      local ok,err=set_relay(msg.relay,msg.value==true,msg.side)
      if ok then desired=msg.value==true end
      local state=snapshot()
      ctx.kernel.log.write(ok and "info" or "error","lightingd","relay command",{
        sender=sender,relay=msg.relay,side=msg.side,value=msg.value,error=err
      },ctx.process.pid)
      reply(sender,{protocol=protocol,op="set",ok=ok,error=err,state=state})
      return
    end

    reply(sender,{protocol=protocol,op=msg.op,ok=false,error="unknown operation"})
  end

  local opened=net.open_management_modems()
  ctx.unit.details={protocol=protocol,manager_id=managerId,management_modems=opened}
  ctx.kernel.log.write("info","lightingd","lighting controller online",ctx.unit.details,ctx.process.pid)

  discover()
  if #relays>0 then
    local ok,err=set_all(desired)
    ctx.kernel.log.write(ok and "info" or "error","lightingd","initial lighting state applied",{
      desired_on=desired,relays=relays,error=err
    },ctx.process.pid)
  else
    lastError="no redstone relays discovered"
    ctx.kernel.log.write("warning","lightingd",lastError,nil,ctx.process.pid)
  end
  heartbeat()

  local timer=os.startTimer(5)
  while true do
    local ev,a,b,c=coroutine.yield("wait_event")
    if ev=="timer" and a==timer then
      if #relays==0 then
        discover()
        if #relays>0 then set_all(desired) end
      end
      heartbeat()
      timer=os.startTimer(5)
    elseif ev=="rednet_message" and c==protocol then
      handle(a,b)
    elseif ev=="peripheral" or ev=="peripheral_detach" then
      discover()
      if #relays>0 then set_all(desired) end
      heartbeat()
    end
  end
end
