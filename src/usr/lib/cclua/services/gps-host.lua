return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local net=dofile("/usr/lib/cclua/net.lua")
  local machine=config.machine()

  local gpsProtocol="cclua-gps-v1"
  local managerProtocol="cclua-manager-v1"
  local gpsChannel=65534
  local controlId=tonumber(machine.gps_control_id) or 14
  local managerId=tonumber(machine.manager_computer_id) or 0

  local x=tonumber(machine.gps_x)
  local y=tonumber(machine.gps_y)
  local z=tonumber(machine.gps_z)
  if not x or not y or not z then error("gps-host requires gps_x/gps_y/gps_z",0) end

  local modem=nil
  local modemName=nil
  local monitor=nil
  local monitorName=nil
  local cache={}
  local requests=0
  local controlAck=0
  local lastError=nil
  local started=os.epoch and os.epoch("utc") or 0

  local function now() return os.epoch and os.epoch("utc") or 0 end

  local function choose_modem()
    modem=nil
    modemName=nil
    for _,name in ipairs(peripheral.getNames()) do
      if peripheral.hasType(name,"modem") then
        local p=peripheral.wrap(name)
        local ok,v=pcall(function() return p.isWireless and p.isWireless() end)
        if ok and v then modemName=name;modem=p;break end
      end
    end
    if modem then
      pcall(rednet.open,modemName)
      pcall(modem.open,gpsChannel)
      lastError=nil
      return true
    end
    lastError="wireless modem unavailable"
    return false
  end

  local function choose_monitor()
    local preferred=machine.monitor_side or "top"
    if peripheral.getType(preferred)=="monitor" then
      monitorName=preferred
      monitor=peripheral.wrap(preferred)
    elseif machine.monitor_strict~=true then
      monitorName=nil
      monitor=peripheral.find("monitor",function(name)
        if not monitorName then monitorName=name;return true end
        return false
      end)
    else
      monitorName=nil
      monitor=nil
    end
    if monitor then
      pcall(monitor.setTextScale,tonumber(machine.monitor_text_scale) or 0.5)
      pcall(monitor.setCursorBlink,false)
      pcall(monitor.setBackgroundColor,colors.black)
      pcall(monitor.setTextColor,colors.white)
      pcall(monitor.clear)
      cache={}
    end
  end

  local function pad(s,w)
    s=tostring(s or "")
    if #s>w then return s:sub(1,w) end
    return s..string.rep(" ",math.max(0,w-#s))
  end

  local function line(yPos,s,fg,bg)
    if not monitor then return end
    local w,h=monitor.getSize()
    if yPos<1 or yPos>h then return end
    s=pad(s,w)
    local key=s.."|"..tostring(fg).."|"..tostring(bg)
    if cache[yPos]==key then return end
    monitor.setCursorPos(1,yPos)
    monitor.setTextColor(fg or colors.white)
    monitor.setBackgroundColor(bg or colors.black)
    monitor.write(s)
    cache[yPos]=key
  end

  local function state()
    local update=config.read_json("/var/lib/cclua/update-state.json",{})
    local ackAge=controlAck>0 and math.max(0,(now()-controlAck)/1000) or math.huge
    local s={
      schema=1,
      computer_id=os.getComputerID(),
      label=machine.label,
      hostname=machine.hostname,
      role=machine.role,
      x=x,y=y,z=z,
      gps_channel=gpsChannel,
      requests_served=requests,
      modem=modemName,
      control_id=controlId,
      control_online=ackAge<8,
      control_age=ackAge<999999 and ackAge or nil,
      update=update,
      healthy=modem~=nil and lastError==nil,
      error=lastError,
      uptime_ms=now()-started,
      timestamp=now()
    }
    config.write_json("/var/lib/cclua/gps-host.json",s)
    config.write_json("/var/log/cclua/gps-host-health.json",s)
    return s
  end

  local function render()
    if not monitor then choose_monitor() end
    if not monitor then return end
    local ok,err=pcall(function()
      local w,h=monitor.getSize()
      local s=state()
      line(1," GPS HOST",colors.white,colors.blue)
      line(2,tostring(machine.label or machine.hostname or "station"),colors.cyan,colors.black)
      line(4,("X %d"):format(x),colors.lightGray,colors.black)
      line(5,("Y %d"):format(y),colors.lightGray,colors.black)
      line(6,("Z %d"):format(z),colors.lightGray,colors.black)
      line(8,("GPS CH %d"):format(gpsChannel),colors.gray,colors.black)
      line(9,("REQ %d"):format(requests),colors.lime,colors.black)
      line(11,s.control_online and "CONTROL LINK OK" or "CONTROL LINK WAIT",
        s.control_online and colors.lime or colors.yellow,colors.black)
      local upd=s.update or {}
      if h>=14 then line(h-2,("UPDATE %s %s%%"):format(
        tostring(upd.state or "CHECKING"),tostring(upd.percent or 0)),colors.gray,colors.black) end
      line(h,s.healthy and "GPS HOST ONLINE" or "GPS HOST FAULT",
        s.healthy and colors.lime or colors.red,colors.black)
    end)
    if not ok then
      lastError="monitor draw: "..tostring(err)
      monitor=nil
    end
  end

  local function send_control_status()
    rednet.send(controlId,{
      protocol=gpsProtocol,
      op="host_status",
      label=machine.label,
      hostname=machine.hostname,
      x=x,y=y,z=z,
      requests_served=requests,
      healthy=modem~=nil and lastError==nil,
      update=config.read_json("/var/lib/cclua/update-state.json",{})
    },gpsProtocol)
  end

  local function send_manager_status()
    local s=state()
    rednet.send(managerId,{
      protocol=managerProtocol,
      op="status",
      hostname=machine.hostname,
      role=machine.role,
      status={
        hostname=machine.hostname,
        role=machine.role,
        system_state=s.healthy and "HEALTHY" or "DEGRADED",
        gps_host={
          x=x,y=y,z=z,requests_served=requests,
          control_online=s.control_online,healthy=s.healthy,error=s.error
        },
        processes=#ctx.kernel.process.all(),
        services=(function()
          local n=0
          for _,u in ipairs(ctx.kernel.services:list()) do if u.state=="active" then n=n+1 end end
          return n
        end)()
      }
    },managerProtocol)
  end

  net.open_management_modems()
  choose_modem()
  choose_monitor()
  ctx.unit.details={
    gps_channel=gpsChannel,modem=modemName,
    control_id=controlId,coords={x=x,y=y,z=z},monitor=monitorName
  }
  ctx.kernel.log.write("info","gps-host","GPS station host online",ctx.unit.details,ctx.process.pid)
  send_control_status()
  send_manager_status()
  render()

  local timer=os.startTimer(2)
  while true do
    local ev,a,b,c,d,e=coroutine.yield("wait_event")
    if ev=="timer" and a==timer then
      if not modem then choose_modem() end
      send_control_status()
      send_manager_status()
      render()
      timer=os.startTimer(2)

    elseif ev=="modem_message" then
      local side,channel,replyChannel,message,distance=a,b,c,d,e
      if side==modemName and channel==gpsChannel and message=="PING" and distance then
        modem.transmit(replyChannel,gpsChannel,{x,y,z})
        requests=requests+1
        render()
      end

    elseif ev=="rednet_message" and a==controlId and c==gpsProtocol and type(b)=="table" then
      if b.op=="host_status" and b.ok then controlAck=now();render() end

    elseif ev=="peripheral" or ev=="peripheral_detach" then
      net.open_management_modems()
      choose_modem()
      choose_monitor()
      render()

    elseif ev=="monitor_resize" then
      choose_monitor()
      render()
    end
  end
end
