return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local net=dofile("/usr/lib/cclua/net.lua")
  local machine=config.machine()
  local protocol="cclua-gps-v1"
  local controlId=tonumber(machine.gps_control_id) or 14
  local pollSeconds=tonumber(machine.gps_monitor_poll_seconds) or 0.25
  local mapCenterX=tonumber(machine.gps_map_center_x) or 20
  local mapCenterZ=tonumber(machine.gps_map_center_z) or 15
  local mapRadius=tonumber(machine.gps_map_radius) or 48

  local monitor=nil
  local monitorName=nil
  local cache={}
  local state=nil
  local lastReply=0
  local trails={}

  local function now()
    return os.epoch and os.epoch("utc") or 0
  end

  local function choose_monitor()
    local preferred=machine.monitor_side or "top"
    if peripheral.getType(preferred)=="monitor" then
      monitorName=preferred
      monitor=peripheral.wrap(preferred)
    elseif machine.monitor_strict~=true then
      monitorName=nil
      monitor=peripheral.find("monitor",function(name)
        if not monitorName then
          monitorName=name
          return true
        end
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

  local function color_char(c)
    return colors.toBlit(c or colors.white)
  end

  local function new_row(w,fg,bg)
    local chars={}
    local fgs={}
    local bgs={}
    local fc=color_char(fg or colors.white)
    local bc=color_char(bg or colors.black)
    for x=1,w do
      chars[x]=" "
      fgs[x]=fc
      bgs[x]=bc
    end
    return {chars=chars,fgs=fgs,bgs=bgs}
  end

  local function set_cell(row,x,ch,fg,bg)
    if not row or x<1 or x>#row.chars then return end
    row.chars[x]=tostring(ch or " "):sub(1,1)
    row.fgs[x]=color_char(fg or colors.white)
    row.bgs[x]=color_char(bg or colors.black)
  end

  local function write_at(row,x,text,fg,bg,maxWidth)
    text=tostring(text or "")
    local width=maxWidth or #text
    for i=1,math.min(#text,width) do
      set_cell(row,x+i-1,text:sub(i,i),fg,bg)
    end
  end

  local function fill(row,x1,x2,ch,fg,bg)
    for x=x1,x2 do set_cell(row,x,ch or " ",fg,bg) end
  end

  local function project(x,z,x1,y1,x2,y2)
    local minX=mapCenterX-mapRadius
    local maxX=mapCenterX+mapRadius
    local minZ=mapCenterZ-mapRadius
    local maxZ=mapCenterZ+mapRadius

    local px=x1+math.floor(((x-minX)/(maxX-minX))*math.max(1,x2-x1))
    local py=y1+math.floor(((z-minZ)/(maxZ-minZ))*math.max(1,y2-y1))

    px=math.max(x1,math.min(x2,px))
    py=math.max(y1,math.min(y2,py))
    return px,py
  end

  local function update_trails()
    if not state then return end
    for _,client in ipairs(state.clients or {}) do
      local id=tostring(client.id or client.label or "?")
      if client.fix and client.x and client.z then
        local trail=trails[id] or {}
        local last=trail[#trail]
        if not last or math.abs(last.x-client.x)>=0.2 or math.abs(last.z-client.z)>=0.2 then
          trail[#trail+1]={x=client.x,z=client.z}
          while #trail>40 do table.remove(trail,1) end
        end
        trails[id]=trail
      end
    end
  end

  local function build_frame()
    if not monitor then return nil end
    local w,h=monitor.getSize()
    local rows={}
    for y=1,h do rows[y]=new_row(w,colors.white,colors.black) end

    local stale=not state or (now()-lastReply)>2000
    fill(rows[1],1,w," ",colors.white,colors.blue)
    write_at(rows[1],2,"CCLUA GPS OPERATIONS",colors.white,colors.blue)
    local right=("CTRL %s"):format(stale and "STALE" or "LINK")
    write_at(rows[1],math.max(2,w-#right),right,
      stale and colors.red or colors.lime,colors.blue)

    local clients=state and (state.clients or {}) or {}
    local hosts=state and (state.hosts or {}) or {}
    local ready=state and state.gps_ready==true
    local header=("GPS %s   HOSTS %d/%d   CLIENTS %d"):format(
      ready and "READY" or "NOT READY",
      state and (state.hosts_online or 0) or 0,
      state and (state.host_count or 0) or 0,
      state and (state.clients_online or 0) or 0
    )
    write_at(rows[2],2,header,ready and colors.lime or colors.orange,colors.black,w-2)

    if not state then
      write_at(rows[5],3,"Waiting for GPS_CONTROL...",colors.yellow,colors.black)
      return rows
    end

    local sidebarW=math.max(28,math.min(36,math.floor(w*0.33)))
    local mapX1=2
    local mapX2=math.max(mapX1+12,w-sidebarW-1)
    local mapY1=4
    local mapY2=math.max(mapY1+8,h-2)
    local sideX=mapX2+3

    -- Map border and labels.
    for x=mapX1,mapX2 do
      set_cell(rows[mapY1],x,"-",colors.gray,colors.black)
      set_cell(rows[mapY2],x,"-",colors.gray,colors.black)
    end
    for y=mapY1,mapY2 do
      set_cell(rows[y],mapX1,"|",colors.gray,colors.black)
      set_cell(rows[y],mapX2,"|",colors.gray,colors.black)
    end
    set_cell(rows[mapY1],mapX1,"+",colors.gray,colors.black)
    set_cell(rows[mapY1],mapX2,"+",colors.gray,colors.black)
    set_cell(rows[mapY2],mapX1,"+",colors.gray,colors.black)
    set_cell(rows[mapY2],mapX2,"+",colors.gray,colors.black)

    local mapTitle=("LOCAL MAP  X%d Z%d  +/- %d"):format(mapCenterX,mapCenterZ,mapRadius)
    write_at(rows[mapY1],mapX1+2,mapTitle,colors.lightBlue,colors.black,mapX2-mapX1-3)

    local innerX1,innerX2=mapX1+1,mapX2-1
    local innerY1,innerY2=mapY1+1,mapY2-1

    -- Center crosshair at configured home center.
    local cx,cy=project(mapCenterX,mapCenterZ,innerX1,innerY1,innerX2,innerY2)
    set_cell(rows[cy],cx,"+",colors.gray,colors.black)

    -- Trails first, then fixed stations, then live clients.
    for id,trail in pairs(trails) do
      for _,pt in ipairs(trail) do
        local tx,ty=project(pt.x,pt.z,innerX1,innerY1,innerX2,innerY2)
        set_cell(rows[ty],tx,".",colors.gray,colors.black)
      end
    end

    for _,host in ipairs(hosts) do
      if host.x and host.z then
        local hx,hz=host.x,host.z
        if math.abs(hx-mapCenterX)<=mapRadius and math.abs(hz-mapCenterZ)<=mapRadius then
          local px,py=project(hx,hz,innerX1,innerY1,innerX2,innerY2)
          set_cell(rows[py],px,"H",host.online and colors.cyan or colors.red,colors.black)
        end
      end
    end

    for _,client in ipairs(clients) do
      if client.x and client.z then
        local px,py=project(client.x,client.z,innerX1,innerY1,innerX2,innerY2)
        local col=(client.online and client.fix) and colors.lime or colors.orange
        set_cell(rows[py],px,"@",col,colors.black)
      end
    end

    -- Sidebar.
    write_at(rows[4],sideX,"MOBILE CLIENTS",colors.cyan,colors.black,sidebarW-1)
    local sy=5
    if #clients==0 then
      write_at(rows[sy],sideX,"No clients online",colors.gray,colors.black,sidebarW-1)
      sy=sy+2
    else
      for _,client in ipairs(clients) do
        if sy>h-9 then break end
        local ok=client.online and client.fix
        write_at(rows[sy],sideX,
          ("%s ID %s  %s"):format(ok and "[+]" or "[!]",
            tostring(client.id or "?"),tostring(client.label or "client")),
          ok and colors.lime or colors.orange,colors.black,sidebarW-1)
        sy=sy+1
        if client.x and client.y and client.z then
          write_at(rows[sy],sideX,
            ("X%7.2f Y%6.2f Z%7.2f"):format(client.x,client.y,client.z),
            colors.lightGray,colors.black,sidebarW-1)
        else
          write_at(rows[sy],sideX,"NO GPS FIX",colors.orange,colors.black,sidebarW-1)
        end
        sy=sy+1
        write_at(rows[sy],sideX,
          ("seq %-5s  %.1fHz  miss %-4s"):format(
            tostring(client.seq or 0),tonumber(client.rate_hz or 0) or 0,tostring(client.misses or 0)),
          colors.gray,colors.black,sidebarW-1)
        sy=sy+2
      end
    end

    local hostY=math.max(sy,math.min(h-7,14))
    if hostY<h-3 then
      write_at(rows[hostY],sideX,"GPS HOSTS",colors.cyan,colors.black,sidebarW-1)
      hostY=hostY+1
      for _,host in ipairs(hosts) do
        if hostY>h-3 then break end
        write_at(rows[hostY],sideX,
          ("%s %-18s"):format(host.online and "[+]" or "[!]",tostring(host.label or ("ID"..tostring(host.id)))),
          host.online and colors.lime or colors.red,colors.black,sidebarW-1)
        hostY=hostY+1
      end
    end

    local legend="H=GPS HOST   @=CLIENT   .=TRAIL"
    write_at(rows[h-1],2,legend,colors.gray,colors.black,math.max(1,w-3))
    local footer=("CONTROL %d | %.2fs refresh | %s"):format(
      controlId,pollSeconds,tostring(monitorName or "monitor"))
    write_at(rows[h],2,footer,colors.gray,colors.black,math.max(1,w-3))

    return rows
  end

  local function render()
    if not monitor then choose_monitor() end
    if not monitor then return end

    update_trails()

    local ok,err=pcall(function()
      local rows=build_frame()
      if not rows then return end
      local w,h=monitor.getSize()

      for y=1,h do
        local row=rows[y]
        local t=table.concat(row.chars)
        local f=table.concat(row.fgs)
        local b=table.concat(row.bgs)
        local key=t.."|"..f.."|"..b

        if cache[y]~=key then
          monitor.setCursorPos(1,y)
          monitor.blit(t,f,b)
          cache[y]=key
        end
      end
    end)

    if not ok then
      ctx.kernel.log.write("warning","gps-monitor","map render failed",{error=tostring(err)},ctx.process.pid)
      monitor=nil
    end
  end

  local function request()
    rednet.send(controlId,{protocol=protocol,op="status"},protocol)
  end

  net.open_management_modems()
  choose_monitor()
  ctx.unit.details={
    protocol=protocol,control_id=controlId,monitor=monitorName,
    poll_seconds=pollSeconds,map_center={x=mapCenterX,z=mapCenterZ},map_radius=mapRadius
  }
  ctx.kernel.log.write("info","gps-monitor","GPS live map monitor online",ctx.unit.details,ctx.process.pid)

  request()
  render()

  local poll=os.startTimer(pollSeconds)
  while true do
    local ev,a,b,c=coroutine.yield("wait_event")

    if ev=="timer" and a==poll then
      request()
      render()
      poll=os.startTimer(pollSeconds)

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
