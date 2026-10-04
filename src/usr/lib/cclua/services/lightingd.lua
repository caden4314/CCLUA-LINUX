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
  local leverSide=settings.lever_side or "front"
  local leverEnabled=settings.lever_enabled~=false
  local lastLever=nil
  local animationActive=false
  local lightMonitor=nil
  local lightMonitorName=nil
  local lightMonitorWidth=0
  local lightMonitorHeight=0
  local expected_state
  local room_summary

  local function pause(ms)
    local wake=(os.epoch and os.epoch("utc") or 0)+(tonumber(ms) or 0)
    coroutine.yield("sleep",wake)
  end

  local function reload_settings()
    settings=config.read_json("/etc/cclua/lighting.json",settings or {})
    leverSide=settings.lever_side or "front"
    leverEnabled=settings.lever_enabled~=false
  end

  local function choose_light_monitor()
    reload_settings()
    if settings.monitor_enabled==false then
      lightMonitor=nil
      lightMonitorName=nil
      lightMonitorWidth=0
      lightMonitorHeight=0
      return nil
    end

    local preferred=settings.monitor_name
    local name=nil
    local mon=nil

    if preferred and peripheral.getType(preferred)=="monitor" then
      name=preferred
      mon=peripheral.wrap(preferred)
    else
      mon=peripheral.find("monitor",function(foundName,obj)
        if not name then
          name=foundName
          return true
        end
        return false
      end)
    end

    if mon then
      pcall(mon.setTextScale,tonumber(settings.monitor_scale) or 0.5)
      pcall(mon.setBackgroundColor,colors.black)
      pcall(mon.setTextColor,colors.white)
      local ok,w,h=pcall(mon.getSize)
      if ok then
        lightMonitorWidth=w or 0
        lightMonitorHeight=h or 0
      else
        lightMonitorWidth=0
        lightMonitorHeight=0
      end
    end

    lightMonitor=mon
    lightMonitorName=name
    return mon
  end

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

  local function room_entries()
    local out={}
    for name,list in pairs(settings.rooms or {}) do
      if type(name)=="string" and type(list)=="table" then
        local relaysForRoom={}
        for _,relay in ipairs(list) do
          if type(relay)=="string" then relaysForRoom[#relaysForRoom+1]=relay end
        end
        table.sort(relaysForRoom,function(a,b)return relay_id(a)<relay_id(b) end)
        out[#out+1]={name=name,relays=relaysForRoom}
      end
    end
    table.sort(out,function(a,b)return a.name:lower()<b.name:lower() end)
    return out
  end

  local function find_room(name)
    local wanted=tostring(name or ""):lower()
    for _,room in ipairs(room_entries()) do
      if room.name:lower()==wanted then return room end
    end
    return nil
  end

  local function relay_present(name)
    return peripheral.hasType(name,"redstone_relay")
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

  local function set_all(value,source)
    discover()
    local errors={}
    for _,name in ipairs(relays) do
      local ok,err=set_relay(name,value)
      if not ok then errors[#errors+1]=name..": "..tostring(err) end
    end
    desired=value==true
    lastError=#errors>0 and table.concat(errors,"; ") or nil
    ctx.kernel.log.write(
      #errors==0 and "info" or "error",
      "lightingd",
      "lighting state "..(desired and "ON" or "OFF"),
      {source=source or "service",relay_count=#relays,error=lastError},
      ctx.process.pid
    )
    return #errors==0,lastError
  end

  local function set_room(roomName,value,source)
    discover()
    local room=find_room(roomName)
    if not room then return nil,"unknown room: "..tostring(roomName) end
    if #room.relays==0 then return nil,"room has no relays: "..room.name end

    local errors={}
    for _,name in ipairs(room.relays) do
      local ok,err=set_relay(name,value)
      if not ok then errors[#errors+1]=name..": "..tostring(err) end
    end
    lastError=#errors>0 and table.concat(errors,"; ") or nil
    ctx.kernel.log.write(
      #errors==0 and "info" or "error",
      "lightingd",
      ("room %s %s"):format(room.name,value and "ON" or "OFF"),
      {room=room.name,value=value==true,source=source or "service",relay_count=#room.relays,error=lastError},
      ctx.process.pid
    )
    return #errors==0,lastError
  end

  local function read_lever()
    if not leverEnabled then return nil end
    local ok,v=pcall(redstone.getInput,leverSide)
    if not ok then
      lastError="lever read failed: "..tostring(v)
      return nil
    end
    return v==true
  end

  local function sync_lever(force)
    local v=read_lever()
    if v==nil then return false end
    if force or lastLever==nil or v~=lastLever then
      local previous=lastLever
      lastLever=v
      if not animationActive then set_all(v,"lever:"..leverSide) end
      ctx.kernel.log.write("info","lightingd","local lighting lever changed",{
        side=leverSide,value=v,previous=previous
      },ctx.process.pid)
      return true
    end
    return false
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

  local function relay_is_on(name)
    local relay=peripheral.wrap(name)
    if not relay or type(relay.getOutput)~="function" then return false end
    for _,side in ipairs(sides) do
      local ok,v=pcall(relay.getOutput,side)
      if ok and v==true then return true end
    end
    return false
  end

  local function render_light_monitor()
    if not lightMonitor or peripheral.getType(lightMonitorName)~="monitor" then
      choose_light_monitor()
    end
    local mon=lightMonitor
    if not mon then return end

    local ok,err=pcall(function()
      local w,h=mon.getSize()
      lightMonitorWidth=w
      lightMonitorHeight=h
      mon.setBackgroundColor(colors.black)
      mon.setTextColor(colors.white)
      mon.clear()

      local function clip(s,n)
        s=tostring(s or "")
        if n<=0 then return "" end
        if #s>n then return s:sub(1,n) end
        return s
      end

      local function line(y,text,fg,bg)
        if y<1 or y>h then return end
        mon.setCursorPos(1,y)
        mon.setBackgroundColor(bg or colors.black)
        mon.setTextColor(fg or colors.white)
        mon.write(clip(text,w))
        local used=math.min(#tostring(text),w)
        if used<w then mon.write(string.rep(" ",w-used)) end
      end

      local function relay_bar(y,startId,endId)
        if y<1 or y>h then return end
        local prefix=(startId==0 and "0-7 " or "8-F ")
        if w<12 then prefix=(startId==0 and "0:" or "8:") end
        mon.setCursorPos(1,y)
        mon.setBackgroundColor(colors.black)
        mon.setTextColor(colors.lightGray)
        mon.write(clip(prefix,w))

        local x=#prefix+1
        for id=startId,endId do
          if x>w then break end
          local name="redstone_relay_"..tostring(id)
          mon.setCursorPos(x,y)
          local present=peripheral.hasType(name,"redstone_relay")
          local on=present and relay_is_on(name)
          mon.setTextColor(not present and colors.red or (on and colors.lime or colors.gray))
          mon.write(not present and "!" or (on and "#" or "."))
          x=x+1
        end
        if x<=w then
          mon.setCursorPos(x,y)
          mon.setBackgroundColor(colors.black)
          mon.write(string.rep(" ",w-x+1))
        end
      end

      line(1," LIGHTING",colors.white,colors.blue)

      local lever=read_lever()
      local lightWord=desired and "ON" or "OFF"
      local leverWord=lever==nil and "--" or (lever and "ON" or "OFF")
      line(2,("LIGHT %-3s L %-3s"):format(lightWord,leverWord),
        desired and colors.lime or colors.lightGray)

      local expected=settings.expected_relays or {}
      local expectedCount=#expected>0 and #expected or #relays
      local okRelays=#relays>=expectedCount
      line(3,("RELAYS %d/%d %s"):format(#relays,expectedCount,okRelays and "OK" or "ERR"),
        okRelays and colors.lime or colors.red)

      if h>=4 then
        local summaries=room_summary()
        if animationActive then
          line(4,"ANIM  RUN",colors.yellow)
        elseif #summaries>0 then
          local r=summaries[1]
          local short=((settings.room_short_names or {})[r.name])
          if not short then
            short=r.name:gsub("[^%w]",""):upper():sub(1,3)
          end
          line(4,("%s %-5s %d/%d"):format(short,r.state,r.present,r.relay_count),
            r.healthy and (r.state=="ON" and colors.lime or colors.lightGray) or colors.red)
        else
          line(4,"ANIM  IDLE",colors.gray)
        end
      end
      if h>=5 then relay_bar(5,0,7) end
      if h>=6 then relay_bar(6,8,15) end

      if h>=7 then
        local fault=lastError
        local _,missing=expected_state()
        if not fault and #missing>0 then fault="MISS "..tostring(#missing) end
        line(h,fault and ("FAULT "..fault) or "STATUS OK",
          fault and colors.red or colors.lime)
      end
    end)

    if not ok then
      ctx.kernel.log.write("warning","lightingd","lighting monitor draw failed",{
        monitor=lightMonitorName,error=tostring(err)
      },ctx.process.pid)
      lightMonitor=nil
      lightMonitorName=nil
    end
  end

  expected_state=function()
    local expected=settings.expected_relays or {}
    local present={}
    for _,name in ipairs(relays) do present[name]=true end
    local missing={}
    for _,name in ipairs(expected) do
      if not present[name] then missing[#missing+1]=name end
    end
    return expected,missing
  end

  room_summary=function()
    local out={}
    for _,room in ipairs(room_entries()) do
      local present,on,missing=0,0,{}
      for _,name in ipairs(room.relays) do
        if relay_present(name) then
          present=present+1
          if relay_is_on(name) then on=on+1 end
        else
          missing[#missing+1]=name
        end
      end
      local state
      if #missing>0 then state="MISSING"
      elseif on==#room.relays and #room.relays>0 then state="ON"
      elseif on==0 then state="OFF"
      else state="MIXED" end
      out[#out+1]={
        name=room.name,
        relay_count=#room.relays,
        present=present,
        on=on,
        off=math.max(0,present-on),
        missing_relays=missing,
        healthy=#missing==0,
        state=state
      }
    end
    return out
  end

  local function snapshot()
    reload_settings()
    discover()
    local items={}
    for _,name in ipairs(relays) do items[#items+1]=relay_state(name) end
    local expected,missing=expected_state()
    local lever=read_lever()
    local state={
      schema=2,
      hostname=machine.hostname,
      computer_id=os.getComputerID(),
      role=machine.role,
      desired_on=desired,
      relay_count=#relays,
      relays=items,
      rooms=room_summary(),
      expected_relays=expected,
      missing_relays=missing,
      lever_enabled=leverEnabled,
      lever_side=leverSide,
      lever_input=lever,
      animation_active=animationActive,
      monitor_name=lightMonitorName,
      monitor_width=lightMonitorWidth,
      monitor_height=lightMonitorHeight,
      healthy=(#relays>0 and #missing==0 and lastError==nil),
      error=lastError,
      timestamp=os.epoch and os.epoch("utc") or 0
    }
    config.write_json("/var/lib/cclua/lighting.json",state)
    config.write_json("/var/log/cclua/lighting-health.json",state)
    render_light_monitor()
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

  local function animate_group(group,label)
    if animationActive then return nil,"animation already running" end
    discover()
    if #group==0 then return nil,"no relays to animate" end

    local restore={}
    for _,name in ipairs(group) do
      if relay_present(name) then restore[name]=relay_is_on(name) end
    end

    animationActive=true
    render_light_monitor()
    local step=tonumber(settings.animation_step_ms) or 70

    ctx.kernel.log.write("info","lightingd","lighting animation started",{
      group=label,relays=#group,step_ms=step
    },ctx.process.pid)

    for _,name in ipairs(group) do if relay_present(name) then set_relay(name,false) end end
    pause(80)

    for _,name in ipairs(group) do
      if relay_present(name) then
        set_relay(name,true)
        render_light_monitor()
        pause(step)
        set_relay(name,false)
        render_light_monitor()
      end
    end

    for _,name in ipairs(group) do if relay_present(name) then set_relay(name,true) end end
    pause(120)
    for _,name in ipairs(group) do
      if restore[name]~=nil then set_relay(name,restore[name]) end
    end

    animationActive=false
    render_light_monitor()
    ctx.kernel.log.write("info","lightingd","lighting animation complete",{
      group=label
    },ctx.process.pid)
    return true
  end

  local function animate_quick()
    discover()
    return animate_group(relays,"all")
  end

  local function animate_room(roomName)
    local room=find_room(roomName)
    if not room then return nil,"unknown room: "..tostring(roomName) end
    return animate_group(room.relays,room.name)
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
      local ok,err=set_all(msg.value==true,"network:"..tostring(sender))
      reply(sender,{protocol=protocol,op="all",ok=ok,error=err,state=snapshot()})
      return
    end

    if msg.op=="set" then
      local ok,err=set_relay(msg.relay,msg.value==true,msg.side)
      ctx.kernel.log.write(ok and "info" or "error","lightingd","relay command",{
        sender=sender,relay=msg.relay,side=msg.side,value=msg.value,error=err
      },ctx.process.pid)
      reply(sender,{protocol=protocol,op="set",ok=ok,error=err,state=snapshot()})
      return
    end

    if msg.op=="rooms" or msg.op=="room_status" then
      local state=snapshot()
      if msg.op=="room_status" and not find_room(msg.room) then
        reply(sender,{protocol=protocol,op=msg.op,ok=false,error="unknown room: "..tostring(msg.room),state=state})
      else
        reply(sender,{protocol=protocol,op=msg.op,ok=true,state=state})
      end
      return
    end

    if msg.op=="room_set" then
      local ok,err=set_room(msg.room,msg.value==true,"network:"..tostring(sender))
      reply(sender,{protocol=protocol,op=msg.op,ok=ok==true,error=err,state=snapshot()})
      return
    end

    if msg.op=="room_animate" then
      local ok,err=animate_room(msg.room)
      reply(sender,{protocol=protocol,op=msg.op,ok=ok==true,error=err,state=snapshot()})
      return
    end

    if msg.op=="animate" then
      local ok,err=animate_quick()
      reply(sender,{protocol=protocol,op="animate",ok=ok==true,error=err,state=snapshot()})
      return
    end

    reply(sender,{protocol=protocol,op=msg.op,ok=false,error="unknown operation"})
  end

  local opened=net.open_management_modems()
  ctx.unit.details={
    protocol=protocol,manager_id=managerId,management_modems=opened,
    lever_side=leverSide
  }
  ctx.kernel.log.write("info","lightingd","lighting controller online",ctx.unit.details,ctx.process.pid)

  discover()
  reload_settings()
  choose_light_monitor()
  local lever=read_lever()
  if leverEnabled and lever~=nil then
    lastLever=lever
    set_all(lever,"lever-initial:"..leverSide)
  elseif #relays>0 then
    set_all(desired,"configured-default")
  else
    lastError="no redstone relays discovered"
    ctx.kernel.log.write("warning","lightingd",lastError,nil,ctx.process.pid)
  end
  heartbeat()

  local timer=os.startTimer(1)
  while true do
    local ev,a,b,c=coroutine.yield("wait_event")
    if ev=="timer" and a==timer then
      reload_settings()
      sync_lever(false)
      heartbeat()
      timer=os.startTimer(2)
    elseif ev=="redstone" then
      sync_lever(false)
      heartbeat()
    elseif ev=="rednet_message" and c==protocol then
      handle(a,b)
    elseif ev=="peripheral" or ev=="peripheral_detach" then
      discover()
      choose_light_monitor()
      if #relays>0 and not animationActive then set_all(desired,"peripheral-change") end
      heartbeat()
    elseif ev=="monitor_resize" then
      choose_light_monitor()
      render_light_monitor()
    end
  end
end
