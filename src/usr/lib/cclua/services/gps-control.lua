return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local net=dofile("/usr/lib/cclua/net.lua")
  local machine=config.machine()
  local protocol="cclua-gps-v1"
  local managerProtocol="cclua-manager-v1"
  local managerId=tonumber(machine.manager_computer_id) or 0
  local expectedHosts=type(machine.gps_expected_hosts)=="table" and machine.gps_expected_hosts or {}
  local hosts={}
  local clients={}
  local monitor=nil
  local monitorName=nil
  local cache={}
  local started=os.epoch and os.epoch("utc") or 0
  local lastPersist=0

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

  local function host_rows()
    local out={}
    local seen={}
    local t=now()

    for id,h in pairs(hosts) do
      local age=math.max(0,(t-(h.last_seen or 0))/1000)
      if age<15 then
        local nid=tonumber(id) or id
        seen[tostring(nid)]=true
        out[#out+1]={
          id=nid,label=h.label or ("gps-host-"..tostring(nid)),
          x=h.x,y=h.y,z=h.z,age=age,online=age<8,
          requests_served=tonumber(h.requests_served) or 0,
          healthy=h.healthy~=false,
          update=h.update
        }
      end
    end

    for _,e in ipairs(expectedHosts) do
      local id=tonumber(e.id)
      if id and not seen[tostring(id)] then
        out[#out+1]={
          id=id,label=e.label or ("gps-host-"..tostring(id)),
          x=tonumber(e.x),y=tonumber(e.y),z=tonumber(e.z),
          age=math.huge,online=false,requests_served=0,
          healthy=false,expected=true
        }
      end
    end

    table.sort(out,function(a,b)
      local ai,bi=tonumber(a.id) or 9999,tonumber(b.id) or 9999
      if ai~=bi then return ai<bi end
      return tostring(a.label)<tostring(b.label)
    end)
    return out
  end

  local function client_rows()
    local out={}
    local t=now()
    for id,client in pairs(clients) do
      local age=math.max(0,(t-(client.last_seen or 0))/1000)
      if age<30 then
        out[#out+1]={
          id=tonumber(id) or id,
          label=client.label or ("gps-client-"..tostring(id)),
          kind=client.kind or "client",
          x=client.x,y=client.y,z=client.z,
          fix=client.fix==true,
          age=age,
          online=age<8,
          fixes=tonumber(client.fixes) or 0,
          misses=tonumber(client.misses) or 0,
          session=client.session,
          seq=tonumber(client.seq) or 0,
          rate_hz=tonumber(client.rate_hz) or 0
        }
      end
    end
    table.sort(out,function(a,b)
      return tostring(a.label)<tostring(b.label)
    end)
    return out
  end

  local function state()
    local hs=host_rows()
    local cs=client_rows()
    local online=0
    local firstY=nil
    local verticalDiversity=false
    for _,h in ipairs(hs) do
      if h.online then
        online=online+1
        if h.y~=nil then
          if firstY==nil then firstY=h.y
          elseif math.abs((tonumber(h.y) or 0)-(tonumber(firstY) or 0))>=2 then
            verticalDiversity=true
          end
        end
      end
    end
    local geometryOk=online>=4 and verticalDiversity
    local update=config.read_json("/var/lib/cclua/update-state.json",{})
    local s={
      schema=1,
      hostname=machine.hostname,
      computer_id=os.getComputerID(),
      role=machine.role,
      status="ONLINE",
      gps_ready=geometryOk,
      geometry_ok=geometryOk,
      vertical_diversity=verticalDiversity,
      host_count=#hs,
      expected_host_count=#expectedHosts,
      hosts_online=online,
      hosts=hs,
      clients=cs,
      clients_online=(function()
        local n=0
        for _,client in ipairs(cs) do if client.online then n=n+1 end end
        return n
      end)(),
      minimum_hosts=4,
      manager_id=managerId,
      update=update,
      uptime_ms=now()-started,
      timestamp=now()
    }
    local t=now()
    if t-lastPersist>=1000 then
      config.write_json("/var/lib/cclua/gps-control.json",s)
      config.write_json("/var/log/cclua/gps-health.json",s)
      lastPersist=t
    end
    return s
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
      local s=state()
      line(1," CCLUA GPS CONTROL",colors.white,colors.blue)
      line(2,(" Controller ID %-3d  %s"):format(os.getComputerID(),machine.hostname or "gps-control"),colors.lightGray,colors.black)
      line(4,"GPS HOST NETWORK",colors.cyan,colors.black)
      line(5,("Hosts online: %d / %d required"):format(s.hosts_online,s.minimum_hosts),
        s.gps_ready and colors.lime or colors.yellow,colors.black)
      local gpsStatus=s.gps_ready and "Status: READY FOR GPS FIXES"
        or ((s.hosts_online or 0)<(s.minimum_hosts or 4)
          and "Status: WAITING FOR GPS HOSTS"
          or "Status: WAITING FOR 3D GEOMETRY")
      line(6,gpsStatus,s.gps_ready and colors.lime or colors.orange,colors.black)

      local y=8
      if #s.hosts==0 then
        line(y,"No GPS hosts enrolled.",colors.gray,colors.black)
        if y+1<=h then line(y+1,"Add 4+ host nodes to enable positioning.",colors.gray,colors.black) end
      else
        line(y,"HOSTS",colors.cyan,colors.black)
        y=y+1
        for _,host in ipairs(s.hosts) do
          if y>h-6 then break end
          local coord=(host.x and host.y and host.z) and
            (" %.0f %.0f %.0f"):format(host.x,host.y,host.z) or " no-coord"
          line(y,("%s ID%d%s req %d"):format(
            host.online and "[+]" or "[!]",host.id,coord,host.requests_served or 0),
            (host.online and host.healthy) and colors.lime or colors.red,colors.black)
          y=y+1
        end
      end

      if y<=h-5 then
        line(y,"MOBILE CLIENTS",colors.cyan,colors.black)
        y=y+1
        if #(s.clients or {})==0 then
          line(y,"No GPS clients online.",colors.gray,colors.black)
        else
          for _,client in ipairs(s.clients or {}) do
            if y>h-4 then break end
            local coord=(client.x and client.y and client.z) and
              (" %.1f %.1f %.1f"):format(client.x,client.y,client.z) or " no-fix"
            line(y,("%s %s%s"):format(
              (client.online and client.fix) and "[+]" or "[!]",
              client.label or ("ID"..tostring(client.id)),coord),
              (client.online and client.fix) and colors.lime or colors.orange,colors.black)
            y=y+1
          end
        end
      end

      local upd=s.update or {}
      if h>=5 then
        line(h-3,("Manager ID %d   Update %s %s%%"):format(
          managerId,tostring(upd.state or "CHECKING"),tostring(upd.percent or 0)
        ),colors.lightGray,colors.black)
        line(h-2,("Image %s"):format(tostring(upd.current_commit or "-"):sub(1,12)),colors.gray,colors.black)
        line(h,"GPS control protocol: "..protocol,colors.gray,colors.black)
      end
    end)
    if not ok then
      ctx.kernel.log.write("warning","gps-control","monitor draw failed",{error=tostring(err)},ctx.process.pid)
      monitor=nil
    end
  end

  local function heartbeat()
    local s=state()
    rednet.send(managerId,{
      protocol=managerProtocol,
      op="status",
      hostname=machine.hostname,
      role=machine.role,
      status={
        hostname=machine.hostname,
        role=machine.role,
        system_state="HEALTHY",
        gps=s,
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
  choose_monitor()
  ctx.unit.details={protocol=protocol,manager_id=managerId,monitor=monitorName}
  ctx.kernel.log.write("info","gps-control","GPS control service online",ctx.unit.details,ctx.process.pid)
  heartbeat()
  render()

  local timer=os.startTimer(1)
  while true do
    local ev,a,b,c=coroutine.yield("wait_event",{"timer","rednet_message","peripheral","peripheral_detach","monitor_resize","terminate"})
    if ev=="timer" and a==timer then
      heartbeat()
      render()
      timer=os.startTimer(2)
    elseif ev=="rednet_message" and c==protocol and type(b)=="table" then
      if b.op=="host_status" then
        hosts[a]={
          label=b.label or b.hostname,
          x=tonumber(b.x),y=tonumber(b.y),z=tonumber(b.z),
          requests_served=tonumber(b.requests_served) or 0,
          healthy=b.healthy~=false,
          update=b.update,
          last_seen=now()
        }
        rednet.send(a,{protocol=protocol,op="host_status",ok=true},protocol)
        render()
      elseif b.op=="client_status" then
        local incomingSession=tostring(b.session or "")
        local incomingSeq=tonumber(b.seq) or 0
        local current=clients[a]
        local accept=true

        if current and incomingSession~="" and current.session==incomingSession then
          accept=incomingSeq>(tonumber(current.seq) or -1)
        end

        if accept then
          clients[a]={
            label=b.label or b.hostname,
            kind=b.kind or "client",
            x=tonumber(b.x),y=tonumber(b.y),z=tonumber(b.z),
            fix=b.fix==true,
            fixes=tonumber(b.fixes) or 0,
            misses=tonumber(b.misses) or 0,
            session=incomingSession,
            seq=incomingSeq,
            rate_hz=tonumber(b.rate_hz) or 0,
            last_seen=now()
          }
          render()
        end

        rednet.send(a,{
          protocol=protocol,op="client_status",ok=true,
          accepted=accept,seq=incomingSeq
        },protocol)
      elseif b.op=="status" then
        rednet.send(a,{protocol=protocol,op="status",ok=true,state=state()},protocol)
      end
    elseif ev=="peripheral" or ev=="peripheral_detach" or ev=="monitor_resize" then
      net.open_management_modems()
      choose_monitor()
      render()
    end
  end
end
