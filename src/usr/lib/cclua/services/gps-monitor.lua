return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local net=dofile("/usr/lib/cclua/net.lua")
  local machine=config.machine()
  local protocol="cclua-gps-v1"
  local controlId=tonumber(machine.gps_control_id) or 14
  local monitor=nil
  local monitorName=nil
  local cache={}
  local state=nil
  local lastReply=0

  local function now() return os.epoch and os.epoch("utc") or 0 end

  local function choose_monitor()
    local preferred=machine.monitor_side or "top"
    if peripheral.getType(preferred)=="monitor" then
      monitorName=preferred
      monitor=peripheral.wrap(preferred)
    elseif machine.monitor_strict~=true then
      monitorName=nil
      monitor=peripheral.find("monitor",function(name)
        if not monitorName then monitorName=name return true end
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

  local function line(y,s,fg,bg)
    if not monitor then return end
    local w,h=monitor.getSize()
    if y<1 or y>h then return end
    s=pad(s,w)
    local key=s.."|"..tostring(fg).."|"..tostring(bg)
    if cache[y]==key then return end
    monitor.setCursorPos(1,y)
    monitor.setTextColor(fg or colors.white)
    monitor.setBackgroundColor(bg or colors.black)
    monitor.write(s)
    cache[y]=key
  end

  local function render()
    if not monitor then choose_monitor() end
    if not monitor then return end
    local ok,err=pcall(function()
      local w,h=monitor.getSize()
      local stale=not state or (now()-lastReply)>5000
      line(1," GPS OPERATIONS",colors.white,colors.blue)
      line(2,("Control ID %d   %s"):format(controlId,stale and "LINK STALE" or "LINK OK"),
        stale and colors.red or colors.lime,colors.black)

      if not state then
        line(5,"Waiting for GPS_CONTROL...",colors.yellow,colors.black)
      else
        line(4,"GPS NETWORK",colors.cyan,colors.black)
        line(5,state.gps_ready and "READY" or "NOT READY",
          state.gps_ready and colors.lime or colors.orange,colors.black)
        line(6,("Hosts online %d/%d required"):format(state.hosts_online or 0,state.minimum_hosts or 4),
          state.gps_ready and colors.lime or colors.yellow,colors.black)

        local y=8
        line(y,"BEACONS / HOSTS",colors.cyan,colors.black)
        y=y+1
        if #(state.hosts or {})==0 then
          line(y,"No hosts enrolled",colors.gray,colors.black)
        else
          for _,host in ipairs(state.hosts or {}) do
            if y>h-4 then break end
            local coords=(host.x and host.y and host.z) and
              (" @ %.0f,%.0f,%.0f"):format(host.x,host.y,host.z) or ""
            line(y,("%s %-18s%s"):format(host.online and "[+]" or "[!]",host.label or ("ID"..host.id),coords),
              host.online and colors.lime or colors.red,colors.black)
            y=y+1
          end
        end

        local upd=state.update or {}
        line(h-2,("Controller update: %s %s%%"):format(
          tostring(upd.state or "CHECKING"),tostring(upd.percent or 0)
        ),colors.gray,colors.black)
      end

      line(h,"CCLUA GPS | "..tostring(monitorName or "monitor"),colors.gray,colors.black)
    end)
    if not ok then
      ctx.kernel.log.write("warning","gps-monitor","monitor draw failed",{error=tostring(err)},ctx.process.pid)
      monitor=nil
    end
  end

  local function request()
    rednet.send(controlId,{protocol=protocol,op="status"},protocol)
  end

  net.open_management_modems()
  choose_monitor()
  ctx.unit.details={protocol=protocol,control_id=controlId,monitor=monitorName}
  ctx.kernel.log.write("info","gps-monitor","GPS wall monitor online",ctx.unit.details,ctx.process.pid)
  request()
  render()

  local poll=os.startTimer(1)
  while true do
    local ev,a,b,c=coroutine.yield("wait_event")
    if ev=="timer" and a==poll then
      request()
      render()
      poll=os.startTimer(1)
    elseif ev=="rednet_message" and a==controlId and c==protocol and type(b)=="table" then
      if b.op=="status" and b.ok and type(b.state)=="table" then
        state=b.state
        lastReply=now()
        render()
      end
    elseif ev=="peripheral" or ev=="peripheral_detach" or ev=="monitor_resize" then
      net.open_management_modems()
      choose_monitor()
      render()
    end
  end
end
