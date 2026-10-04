return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local net=dofile("/usr/lib/cclua/net.lua")
  local machine=config.machine()

  local protocol="cclua-lighting-v1"
  local managerProtocol="cclua-manager-v1"
  local managerId=tonumber(machine.manager_computer_id) or 0
  local CONTROL_STATE="/var/lib/cclua/lighting-control.json"

  local settings=config.read_json("/etc/cclua/lighting.json",{})
  local sides={"top","bottom","left","right","front","back"}
  local relays={}
  local relayOnCache={}
  local roomDesired={}
  local monitors={}
  local lastError=nil
  local desired=settings.default_on~=false
  local leverEnabled=settings.lever_enabled~=false
  local leverSide=settings.lever_side or "front"
  local lastLever=nil
  local animationRoom=nil

  local function pause(ms)
    local wake=(os.epoch and os.epoch("utc") or 0)+(tonumber(ms) or 0)
    coroutine.yield("sleep",wake)
  end

  local function reload_settings()
    settings=config.read_json("/etc/cclua/lighting.json",settings or {})
    leverEnabled=settings.lever_enabled~=false
    leverSide=settings.lever_side or "front"
  end

  local function relay_id(name)
    return tonumber(tostring(name):match("_(%d+)$")) or 99999
  end

  local function discover_relays()
    local found={}
    for _,name in ipairs(peripheral.getNames()) do
      if peripheral.hasType(name,"redstone_relay") then found[#found+1]=name end
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
        local rs={}
        for _,relay in ipairs(list) do
          if type(relay)=="string" then rs[#rs+1]=relay end
        end
        table.sort(rs,function(a,b)return relay_id(a)<relay_id(b) end)
        out[#out+1]={name=name,relays=rs}
      end
    end

    local order=settings.room_order or {}
    local rank={}
    for i,name in ipairs(order) do rank[tostring(name)]=i end
    table.sort(out,function(a,b)
      local ar=rank[a.name] or 999
      local br=rank[b.name] or 999
      if ar~=br then return ar<br end
      return a.name:lower()<b.name:lower()
    end)
    return out
  end

  local function find_room(name)
    local wanted=tostring(name or ""):lower()
    for _,room in ipairs(room_entries()) do
      if room.name:lower()==wanted then return room end
    end
    return nil
  end

  local function load_control_state()
    local saved=config.read_json(CONTROL_STATE,{})
    roomDesired=type(saved.rooms)=="table" and saved.rooms or {}
  end

  local function save_control_state()
    config.write_json(CONTROL_STATE,{
      schema=2,
      rooms=roomDesired,
      updated_at=os.epoch and os.epoch("utc") or 0
    })
  end

  local function relay_present(name)
    return peripheral.hasType(name,"redstone_relay")
  end

  local function read_relay_on(name)
    local relay=peripheral.wrap(name)
    if not relay or type(relay.getOutput)~="function" then return false end

    -- CCLUA always drives every output side of a relay together. Reading one
    -- side is therefore enough to determine the logical relay state, and avoids
    -- six synchronous peripheral calls per relay on every health scan.
    local ok,v=pcall(relay.getOutput,"top")
    if ok then return v==true end

    -- Fallback for an unusual/older relay implementation.
    for _,side in ipairs(sides) do
      ok,v=pcall(relay.getOutput,side)
      if ok then return v==true end
    end
    return false
  end

  local function refresh_relay_cache()
    local present={}
    for _,name in ipairs(relays) do
      present[name]=true
      relayOnCache[name]=read_relay_on(name)
    end
    for name in pairs(relayOnCache) do
      if not present[name] then relayOnCache[name]=nil end
    end
  end

  local function relay_is_on(name)
    local cached=relayOnCache[name]
    if cached~=nil then return cached end
    local v=read_relay_on(name)
    relayOnCache[name]=v
    return v
  end

  local function relay_state(name)
    local on=relay_is_on(name)
    -- Preserve the existing state-file shape for cclua-lightctl and older
    -- consumers while treating the six outputs as one logical lamp channel.
    local outputs={}
    for _,side in ipairs(sides) do outputs[side]=on end
    return {name=name,id=relay_id(name),on=on,outputs=outputs}
  end

  local function set_relay(name,value,side)
    if not relay_present(name) then return nil,"relay not present: "..tostring(name) end
    local relay=peripheral.wrap(name)
    if not relay or type(relay.setOutput)~="function" then
      return nil,"relay has no setOutput: "..tostring(name)
    end

    if side then
      local ok,err=pcall(relay.setOutput,side,value==true)
      if not ok then return nil,tostring(err) end
      -- A per-side write is rare/debug-only. Invalidate the aggregate cache so
      -- the next status scan samples hardware again.
      relayOnCache[name]=nil
    else
      for _,s in ipairs(sides) do
        local ok,err=pcall(relay.setOutput,s,value==true)
        if not ok then return nil,tostring(err) end
      end
      relayOnCache[name]=value==true
    end
    return true
  end

  local function room_summary()
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
        desired=roomDesired[room.name],
        state=state
      }
    end
    return out
  end

  local function summary_for(name)
    for _,r in ipairs(room_summary()) do
      if r.name==name then return r end
    end
    return nil
  end

  local function set_room(roomName,value,source)
    discover_relays()
    local room=find_room(roomName)
    if not room then return nil,"unknown room: "..tostring(roomName) end
    if #room.relays==0 then return nil,"room has no relays: "..room.name end

    local errors={}
    for _,name in ipairs(room.relays) do
      local ok,err=set_relay(name,value)
      if not ok then errors[#errors+1]=name..": "..tostring(err) end
    end

    roomDesired[room.name]=value==true
    save_control_state()
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

  local function set_all(value,source)
    discover_relays()
    local errors={}
    for _,name in ipairs(relays) do
      local ok,err=set_relay(name,value)
      if not ok then errors[#errors+1]=name..": "..tostring(err) end
    end

    desired=value==true
    for _,room in ipairs(room_entries()) do roomDesired[room.name]=desired end
    save_control_state()
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
      if not animationRoom then set_all(v,"lever:"..leverSide) end
      ctx.kernel.log.write("info","lightingd","local lighting lever changed",{
        side=leverSide,value=v,previous=previous
      },ctx.process.pid)
      return true
    end
    return false
  end

  local function expected_state()
    local expected=settings.expected_relays or {}
    local present={}
    for _,name in ipairs(relays) do present[name]=true end
    local missing={}
    for _,name in ipairs(expected) do
      if not present[name] then missing[#missing+1]=name end
    end
    return expected,missing
  end

  local function new_row(w,fg,bg)
    local chars,fgs,bgs={},{},{}
    local f=colors.toBlit(fg or colors.white)
    local b=colors.toBlit(bg or colors.black)
    for i=1,w do chars[i]=" ";fgs[i]=f;bgs[i]=b end
    return {chars=chars,fgs=fgs,bgs=bgs}
  end

  local function row_put(row,x,text,fg,bg)
    text=tostring(text or "")
    local f=colors.toBlit(fg or colors.white)
    local b=colors.toBlit(bg or colors.black)
    for i=1,#text do
      local at=x+i-1
      if at>=1 and at<=#row.chars then
        row.chars[at]=text:sub(i,i)
        row.fgs[at]=f
        row.bgs[at]=b
      end
    end
  end

  local function row_fill(row,x1,x2,bg,fg,char)
    local f=colors.toBlit(fg or colors.white)
    local b=colors.toBlit(bg or colors.black)
    for i=math.max(1,x1),math.min(#row.chars,x2) do
      row.chars[i]=char or " "
      row.fgs[i]=f
      row.bgs[i]=b
    end
  end

  local function row_center(row,text,fg,bg,x1,x2)
    x1=x1 or 1
    x2=x2 or #row.chars
    text=tostring(text or "")
    local width=x2-x1+1
    if #text>width then text=text:sub(1,width) end
    local x=x1+math.floor((width-#text)/2)
    row_put(row,x,text,fg,bg)
  end

  local function serialize_row(row)
    return table.concat(row.chars),table.concat(row.fgs),table.concat(row.bgs)
  end

  local function discover_monitors()
    reload_settings()
    local mapping=settings.monitor_rooms or {}
    local wanted={}
    local available={}
    local assigned={}
    local missing={}

    for _,name in ipairs(peripheral.getNames()) do
      if peripheral.getType(name)=="monitor" then available[name]=true end
    end

    local function attach(name,roomName)
      local mon=peripheral.wrap(name)
      if not mon then return end
      pcall(mon.setTextScale,tonumber(settings.monitor_scale) or 0.5)
      pcall(mon.setCursorBlink,false)
      local ok,w,h=pcall(mon.getSize)
      if not ok then return end

      local old=monitors[name]
      local changed=not old or old.w~=w or old.h~=h or old.room~=roomName
      local item=old or {name=name,cache={},zones={}}
      item.mon=mon
      item.room=roomName
      item.w=w
      item.h=h

      if changed then
        item.cache={}
        item.zones={}
        pcall(mon.setBackgroundColor,colors.black)
        pcall(mon.setTextColor,colors.white)
        pcall(mon.clear)
      end

      wanted[name]=item
      assigned[name]=true
    end

    for name,roomName in pairs(mapping) do
      if find_room(roomName) then
        if available[name] then attach(name,roomName)
        else missing[#missing+1]={name=name,room=roomName} end
      end
    end

    -- If exactly one configured panel disappeared and exactly one new monitor
    -- appeared on the lighting bus, safely treat it as a replacement panel.
    -- This handles broken/replaced CC monitors whose peripheral ID changes.
    if settings.monitor_auto_rebind~=false and #missing==1 then
      local unassigned={}
      for name in pairs(available) do
        if not assigned[name] and not mapping[name] then unassigned[#unassigned+1]=name end
      end
      table.sort(unassigned)

      if #unassigned==1 then
        local oldName=missing[1].name
        local roomName=missing[1].room
        local newName=unassigned[1]

        mapping[oldName]=nil
        mapping[newName]=roomName
        settings.monitor_rooms=mapping
        config.write_json("/etc/cclua/lighting.json",settings)

        ctx.kernel.log.write("info","lightingd","lighting monitor automatically rebound",{
          room=roomName,old_monitor=oldName,new_monitor=newName
        },ctx.process.pid)

        monitors=wanted
        return discover_monitors()
      end
    end

    monitors=wanted
    return monitors
  end

  local function render_monitor(item,force)
    local mon=item.mon
    if not mon or peripheral.getType(item.name)~="monitor" then return false end

    local ok,w,h=pcall(mon.getSize)
    if not ok then return false end
    if w~=item.w or h~=item.h then
      item.w=w;item.h=h;item.cache={};item.zones={}
      pcall(mon.clear)
      force=true
    end

    local summary=summary_for(item.room)
    if not summary then return false end

    local rows={}
    for y=1,h do rows[y]=new_row(w,colors.white,colors.black) end
    item.zones={}

    -- Header: compact and consistent on every room panel.
    row_fill(rows[1],1,w,colors.blue,colors.white)
    row_center(rows[1],"LIGHTING",colors.white,colors.blue)

    row_center(rows[2],item.room:upper(),colors.cyan,colors.black)

    local healthText=("%d/%d RELAYS"):format(summary.present or 0,summary.relay_count or 0)
    row_center(rows[3],healthText,summary.healthy and colors.lime or colors.red,colors.black)

    local statusColor=colors.lightGray
    if not summary.healthy then statusColor=colors.red
    elseif summary.state=="ON" then statusColor=colors.lime
    elseif summary.state=="MIXED" then statusColor=colors.orange end

    if h>=5 then
      row_put(rows[5],2,"STATE",colors.gray,colors.black)
      row_put(rows[5],math.max(8,w-4),summary.state,statusColor,colors.black)
    end

    -- Two compact side-by-side state buttons.
    local buttonY1=8
    local buttonY2=10
    if h<16 then buttonY1=6;buttonY2=8 end
    local gap=1
    local leftX1=1
    local leftX2=math.floor((w-gap)/2)
    local rightX1=leftX2+gap+1
    local rightX2=w

    local offSelected=summary.state=="OFF"
    local onSelected=summary.state=="ON"
    local offBg=offSelected and colors.gray or colors.lightGray
    local offFg=offSelected and colors.white or colors.black
    local onBg=onSelected and colors.green or colors.lightGray
    local onFg=onSelected and colors.white or colors.black

    for y=buttonY1,buttonY2 do
      row_fill(rows[y],leftX1,leftX2,offBg,offFg)
      row_fill(rows[y],rightX1,rightX2,onBg,onFg)
    end
    row_center(rows[math.floor((buttonY1+buttonY2)/2)],"OFF",offFg,offBg,leftX1,leftX2)
    row_center(rows[math.floor((buttonY1+buttonY2)/2)],"ON",onFg,onBg,rightX1,rightX2)

    item.zones[#item.zones+1]={action="set",value=false,x1=leftX1,x2=leftX2,y1=buttonY1,y2=buttonY2}
    item.zones[#item.zones+1]={action="set",value=true,x1=rightX1,x2=rightX2,y1=buttonY1,y2=buttonY2}

    -- Small room-only effect control.
    local fxY1=13
    local fxY2=15
    if h<20 then fxY1=10;fxY2=12 end
    if fxY2<=h-2 then
      local fxActive=animationRoom==item.room or animationRoom=="all"
      local fxBg=fxActive and colors.orange or colors.purple
      for y=fxY1,fxY2 do row_fill(rows[y],2,w-1,fxBg,colors.white) end
      row_center(rows[math.floor((fxY1+fxY2)/2)],fxActive and "RUNNING" or "ANIMATE",colors.white,fxBg,2,w-1)
      item.zones[#item.zones+1]={action="animate",x1=2,x2=w-1,y1=fxY1,y2=fxY2}
    end

    -- One-line view of the other room. Status only, not another giant control.
    local other=nil
    for _,r in ipairs(room_summary()) do
      if r.name~=item.room then other=r break end
    end
    local otherY=h-4
    if other and otherY>fxY2 then
      row_put(rows[otherY],1,"OTHER",colors.gray,colors.black)
      local short=((settings.room_short_names or {})[other.name]) or other.name
      local text=(short.." "..other.state)
      if #text>w then text=text:sub(1,w) end
      row_center(rows[otherY+1],text,
        other.healthy and (other.state=="ON" and colors.lime or colors.lightGray) or colors.red,
        colors.black)
    end

    local footer=h
    local footerText
    local footerColor
    if lastError then
      footerText="FAULT"
      footerColor=colors.red
    elseif animationRoom then
      footerText="EFFECT ACTIVE"
      footerColor=colors.yellow
    else
      footerText="TOUCH CONTROL"
      footerColor=colors.gray
    end
    row_center(rows[footer],footerText,footerColor,colors.black)

    for y=1,h do
      local text,fg,bg=serialize_row(rows[y])
      local key=text.."|"..fg.."|"..bg
      if force or item.cache[y]~=key then
        mon.setCursorPos(1,y)
        mon.blit(text,fg,bg)
        item.cache[y]=key
      end
    end

    return true
  end

  local function render_all(force)
    discover_monitors()
    for _,item in pairs(monitors) do
      local ok,err=pcall(render_monitor,item,force==true)
      if not ok then
        ctx.kernel.log.write("warning","lightingd","lighting monitor draw failed",{
          monitor=item.name,room=item.room,error=tostring(err)
        },ctx.process.pid)
      end
    end
  end

  local function handle_monitor_touch(name,x,y)
    local item=monitors[name]
    if not item or animationRoom then return false end

    for _,zone in ipairs(item.zones or {}) do
      if x>=zone.x1 and x<=zone.x2 and y>=zone.y1 and y<=zone.y2 then
        if zone.action=="set" then
          local ok,err=set_room(item.room,zone.value,"touch:"..name)
          ctx.kernel.log.write(ok and "info" or "error","lightingd","touch room set",{
            monitor=name,room=item.room,value=zone.value,x=x,y=y,error=err
          },ctx.process.pid)
          render_all(false)
          return true
        elseif zone.action=="animate" then
          os.queueEvent("cclua_lighting_room_animation",item.room,name)
          return true
        end
      end
    end
    return false
  end

  local function snapshot()
    reload_settings()
    discover_relays()
    refresh_relay_cache()
    discover_monitors()

    local items={}
    for _,name in ipairs(relays) do items[#items+1]=relay_state(name) end
    local expected,missing=expected_state()
    local lever=read_lever()

    local monitorState={}
    for name,item in pairs(monitors) do
      monitorState[#monitorState+1]={
        name=name,room=item.room,width=item.w,height=item.h
      }
    end
    table.sort(monitorState,function(a,b)return a.name<b.name end)

    local state={
      schema=4,
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
      animation_active=animationRoom~=nil,
      animation_room=animationRoom,
      monitors=monitorState,
      monitor_count=#monitorState,
      healthy=(#relays>0 and #missing==0 and lastError==nil),
      error=lastError,
      timestamp=os.epoch and os.epoch("utc") or 0
    }

    config.write_json("/var/lib/cclua/lighting.json",state)
    config.write_json("/var/log/cclua/lighting-health.json",state)
    render_all(false)
    return state
  end

  local function heartbeat()
    local state=snapshot()
    local compactLighting={
      schema=state.schema,
      hostname=state.hostname,
      computer_id=state.computer_id,
      healthy=state.healthy,
      relay_count=state.relay_count,
      expected_relay_count=#(state.expected_relays or {}),
      rooms=state.rooms,
      monitors=state.monitors,
      monitor_count=state.monitor_count,
      animation_active=state.animation_active,
      animation_room=state.animation_room,
      error=state.error,
      timestamp=state.timestamp
    }

    rednet.send(managerId,{
      protocol=managerProtocol,
      op="status",
      hostname=machine.hostname,
      role=machine.role,
      status={
        hostname=machine.hostname,
        role=machine.role,
        system_state=state.healthy and "HEALTHY" or "DEGRADED",
        lighting=compactLighting,
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
    if animationRoom then return nil,"animation already running" end
    discover_relays()
    if #group==0 then return nil,"no relays to animate" end

    refresh_relay_cache()
    local restore={}
    for _,name in ipairs(group) do
      if relay_present(name) then restore[name]=relay_is_on(name) end
    end

    animationRoom=label
    render_all(false)
    local step=tonumber(settings.animation_step_ms) or 70

    ctx.kernel.log.write("info","lightingd","lighting animation started",{
      room=label,relays=#group,step_ms=step
    },ctx.process.pid)

    for _,name in ipairs(group) do if relay_present(name) then set_relay(name,false) end end
    pause(80)

    for _,name in ipairs(group) do
      if relay_present(name) then
        set_relay(name,true)
        pause(step)
        set_relay(name,false)
      end
    end

    for _,name in ipairs(group) do if relay_present(name) then set_relay(name,true) end end
    pause(120)

    for _,name in ipairs(group) do
      if restore[name]~=nil then set_relay(name,restore[name]) end
    end

    animationRoom=nil
    render_all(false)
    ctx.kernel.log.write("info","lightingd","lighting animation complete",{room=label},ctx.process.pid)
    return true
  end

  local function animate_all()
    discover_relays()
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

  local function handle_network(sender,msg)
    if sender~=managerId then
      ctx.kernel.log.write("warning","lightingd","rejected lighting command from unauthorized sender",{sender=sender},ctx.process.pid)
      return
    end
    if type(msg)~="table" or msg.protocol~=protocol then return end

    if msg.op=="status" or msg.op=="discover" or msg.op=="rooms" or msg.op=="room_status" then
      if msg.op=="room_status" and not find_room(msg.room) then
        reply(sender,{protocol=protocol,op=msg.op,ok=false,error="unknown room: "..tostring(msg.room),state=snapshot()})
      else
        reply(sender,{protocol=protocol,op=msg.op,ok=true,state=snapshot()})
      end
      return
    end

    if msg.op=="all" then
      local ok,err=set_all(msg.value==true,"network:"..tostring(sender))
      reply(sender,{protocol=protocol,op=msg.op,ok=ok==true,error=err,state=snapshot()})
      return
    end

    if msg.op=="set" then
      local ok,err=set_relay(msg.relay,msg.value==true,msg.side)
      ctx.kernel.log.write(ok and "info" or "error","lightingd","relay command",{
        sender=sender,relay=msg.relay,side=msg.side,value=msg.value,error=err
      },ctx.process.pid)
      reply(sender,{protocol=protocol,op=msg.op,ok=ok==true,error=err,state=snapshot()})
      return
    end

    if msg.op=="room_set" then
      local ok,err=set_room(msg.room,msg.value==true,"network:"..tostring(sender))
      reply(sender,{protocol=protocol,op=msg.op,ok=ok==true,error=err,state=snapshot()})
      return
    end

    if msg.op=="animate" then
      local ok,err=animate_all()
      reply(sender,{protocol=protocol,op=msg.op,ok=ok==true,error=err,state=snapshot()})
      return
    end

    if msg.op=="room_animate" then
      local ok,err=animate_room(msg.room)
      reply(sender,{protocol=protocol,op=msg.op,ok=ok==true,error=err,state=snapshot()})
      return
    end

    reply(sender,{protocol=protocol,op=msg.op,ok=false,error="unknown operation"})
  end

  local opened=net.open_management_modems()
  ctx.unit.details={protocol=protocol,manager_id=managerId,management_modems=opened}
  ctx.kernel.log.write("info","lightingd","lighting controller online",ctx.unit.details,ctx.process.pid)

  reload_settings()
  discover_relays()
  load_control_state()
  discover_monitors()

  local lever=read_lever()
  if leverEnabled and lever~=nil then
    lastLever=lever
    set_all(lever,"lever-initial:"..leverSide)
  elseif #relays>0 then
    local rooms=room_entries()
    if #rooms>0 then
      for _,room in ipairs(rooms) do
        local value=roomDesired[room.name]
        if value==nil then value=settings.default_on~=false end
        set_room(room.name,value,"persisted-state")
      end
    else
      set_all(desired,"configured-default")
    end
  else
    lastError="no redstone relays discovered"
    ctx.kernel.log.write("warning","lightingd",lastError,nil,ctx.process.pid)
  end

  render_all(true)
  heartbeat()

  local timer=os.startTimer(2)
  local peripheralRefreshTimer=nil
  local peripheralEventCount=0
  local peripheralLastName=nil

  local function schedule_peripheral_refresh(name)
    peripheralEventCount=peripheralEventCount+1
    peripheralLastName=name
    if peripheralRefreshTimer and os.cancelTimer then
      pcall(os.cancelTimer,peripheralRefreshTimer)
    end
    peripheralRefreshTimer=os.startTimer(0.40)
  end

  local function run_peripheral_refresh()
    local count=peripheralEventCount
    local lastName=peripheralLastName
    peripheralRefreshTimer=nil
    peripheralEventCount=0
    peripheralLastName=nil

    discover_relays()
    discover_monitors()
    render_all(true)
    heartbeat()

    ctx.kernel.log.write("info","lightingd","debounced peripheral refresh",{
      batched_events=count,
      last_peripheral=lastName,
      relay_count=#relays
    },ctx.process.pid)
  end

  while true do
    local ev,a,b,c=coroutine.yield("wait_event")

    if ev=="timer" and a==timer then
      reload_settings()
      sync_lever(false)
      if not peripheralRefreshTimer then heartbeat() end
      timer=os.startTimer(2)

    elseif ev=="timer" and peripheralRefreshTimer and a==peripheralRefreshTimer then
      run_peripheral_refresh()

    elseif ev=="redstone" then
      if sync_lever(false) then heartbeat() end

    elseif ev=="rednet_message" and c==protocol then
      handle_network(a,b)

    elseif ev=="monitor_touch" then
      if handle_monitor_touch(a,b,c) then heartbeat() end

    elseif ev=="cclua_lighting_room_animation" then
      local roomName=a
      local source=b
      local ok,err=animate_room(roomName)
      ctx.kernel.log.write(ok and "info" or "error","lightingd","touch room animation",{
        monitor=source,room=roomName,error=err
      },ctx.process.pid)
      heartbeat()

    elseif ev=="peripheral" or ev=="peripheral_detach" then
      schedule_peripheral_refresh(a)

    elseif ev=="monitor_resize" then
      discover_monitors()
      render_all(true)

    elseif ev=="terminate" then
      return 0
    end
  end
end
