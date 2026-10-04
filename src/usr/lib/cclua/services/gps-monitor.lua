return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local net=dofile("/usr/lib/cclua/net.lua")
  local pixelbox=dofile("/usr/lib/cclua/ui/pixelbox_lite.lua")
  local machine=config.machine()
  local protocol="cclua-gps-v1"
  local controlId=tonumber(machine.gps_control_id) or 14
  local pollSeconds=tonumber(machine.gps_monitor_poll_seconds) or 0.10
  local mapCenterX=tonumber(machine.gps_map_center_x) or 20
  local mapCenterZ=tonumber(machine.gps_map_center_z) or 15
  local mapRadius=tonumber(machine.gps_map_radius) or 48
  local invertX=machine.gps_map_invert_x==true
  local invertY=machine.gps_map_invert_y==true
  local rotation=tonumber(machine.gps_map_rotation) or 90
  local terrainPath=machine.gps_terrain_path or "/var/lib/cclua/gps-terrain.lua"

  local monitor,monitorName,mapWindow,box=nil,nil,nil,nil
  local state,lastReply=nil,0
  local trails={}
  local textCache={}
  local terrain=nil

  local function now()
    return os.epoch and os.epoch("utc") or 0
  end

  local function load_terrain()
    if fs.exists(terrainPath) then
      local ok,data=pcall(dofile,terrainPath)
      if ok and type(data)=="table" and type(data.rows)=="table" then
        terrain=data
        return true
      end
    end
    terrain=nil
    return false
  end

  local function blit_to_color(ch)
    local n=tonumber(ch or "f",16)
    if not n then return colors.black end
    return 2^n
  end

  local function text_line(y,text,fg,bg)
    if not monitor then return end
    local w=select(1,monitor.getSize())
    text=tostring(text or "")
    if #text<w then text=text..string.rep(" ",w-#text) end
    if #text>w then text=text:sub(1,w) end
    local key=text.."|"..tostring(fg).."|"..tostring(bg)
    if textCache[y]==key then return end
    monitor.setCursorPos(1,y)
    monitor.setBackgroundColor(bg or colors.black)
    monitor.setTextColor(fg or colors.white)
    monitor.write(text)
    textCache[y]=key
  end

  local function choose_monitor()
    local preferred=machine.monitor_side or "top"
    if peripheral.getType(preferred)=="monitor" then
      monitorName=preferred
      monitor=peripheral.wrap(preferred)
    elseif machine.monitor_strict~=true then
      monitorName=nil
      monitor=peripheral.find("monitor",function(name)
        if monitorName then return false end
        monitorName=name
        return true
      end)
    else
      monitorName=nil
      monitor=nil
    end
    if not monitor then return end
    pcall(monitor.setTextScale,tonumber(machine.monitor_text_scale) or 0.5)
    pcall(monitor.setCursorBlink,false)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()
    textCache={}

    local w,h=monitor.getSize()
    local sidebarW=math.max(27,math.min(34,math.floor(w*0.30)))
    local mapW=math.max(8,w-sidebarW-2)
    local mapH=math.max(6,h-6)
    mapWindow=window.create(monitor,2,4,mapW,mapH,false)
    box=pixelbox.new(mapWindow,colors.black)
    mapWindow.setVisible(true)
  end

  local function normalize_rotation(value)
    value=math.floor((tonumber(value) or 0)/90+0.5)*90
    value=((value%360)+360)%360
    return value
  end

  rotation=normalize_rotation(rotation)

  local function oriented_to_world(sx,sy)
    if invertX then sx=-sx end
    if invertY then sy=-sy end
    local dx,dz
    if rotation==90 then
      dx=-sy
      dz=sx
    elseif rotation==180 then
      dx=-sx
      dz=-sy
    elseif rotation==270 then
      dx=sy
      dz=-sx
    else
      dx=sx
      dz=sy
    end
    return mapCenterX+dx*mapRadius,mapCenterZ+dz*mapRadius
  end

  local function world_to_oriented(wx,wz)
    local dx=(wx-mapCenterX)/mapRadius
    local dz=(wz-mapCenterZ)/mapRadius
    local sx,sy
    if rotation==90 then
      sx=dz
      sy=-dx
    elseif rotation==180 then
      sx=-dx
      sy=-dz
    elseif rotation==270 then
      sx=-dz
      sy=dx
    else
      sx=dx
      sy=dz
    end
    if invertX then sx=-sx end
    if invertY then sy=-sy end
    return sx,sy
  end

  local function screen_to_world(px,py)
    local sx=((px-1)/math.max(1,box.width-1))*2-1
    local sy=((py-1)/math.max(1,box.height-1))*2-1
    return oriented_to_world(sx,sy)
  end

  local function world_to_screen(wx,wz)
    local sx,sy=world_to_oriented(wx,wz)
    local px=1+math.floor(((sx+1)*0.5)*math.max(1,box.width-1)+0.5)
    local py=1+math.floor(((sy+1)*0.5)*math.max(1,box.height-1)+0.5)
    return px,py
  end

  local function terrain_code(wx,wz)
    if not terrain then return nil end
    local minX=tonumber(terrain.min_x) or (mapCenterX-mapRadius)
    local minZ=tonumber(terrain.min_z) or (mapCenterZ-mapRadius)
    local tx=math.floor(wx-minX+1.5)
    local tz=math.floor(wz-minZ+1.5)
    local row=terrain.rows[tz]
    if not row or tx<1 or tx>#row then return nil end
    return row:sub(tx,tx)
  end

  local function structure_code(code)
    return code and code~="4" and code~="f"
  end

  local function schematic_color(wx,wz)
    local code=terrain_code(wx,wz)
    if not structure_code(code) then return colors.black end
    if code=="e" then return colors.red end
    local edge=false
    if not structure_code(terrain_code(wx+1,wz)) then edge=true end
    if not structure_code(terrain_code(wx-1,wz)) then edge=true end
    if not structure_code(terrain_code(wx,wz+1)) then edge=true end
    if not structure_code(terrain_code(wx,wz-1)) then edge=true end
    return edge and colors.lightGray or colors.gray
  end

  local function set_pixel(x,y,c)
    if not box or x<1 or y<1 or x>box.width or y>box.height then return end
    box.canvas[y][x]=c
  end

  local function marker(x,y,c,r)
    r=r or 1
    for dy=-r,r do
      for dx=-r,r do
        if math.abs(dx)+math.abs(dy)<=r+1 then set_pixel(x+dx,y+dy,c) end
      end
    end
  end

  local function update_trails()
    if not state then return end
    for _,client in ipairs(state.clients or {}) do
      if client.fix and client.x and client.z then
        local id=tostring(client.id or client.label or "?")
        local trail=trails[id] or {}
        local last=trail[#trail]
        if not last or math.abs(last.x-client.x)>=0.10 or math.abs(last.z-client.z)>=0.10 then
          trail[#trail+1]={x=client.x,z=client.z}
          while #trail>120 do table.remove(trail,1) end
        end
        trails[id]=trail
      end
    end
  end
  local function render_map()
    if not box then return end
    for py=1,box.height do
      local row=box.canvas[py]
      for px=1,box.width do
        local wx,wz=screen_to_world(px,py)
        row[px]=schematic_color(wx,wz)
      end
    end

    for _,trail in pairs(trails) do
      for i,pt in ipairs(trail) do
        local px,py=world_to_screen(pt.x,pt.z)
        local age=(#trail-i)/math.max(1,#trail)
        set_pixel(px,py,age>0.65 and colors.gray or colors.lightGray)
      end
    end

    if state then
      for _,host in ipairs(state.hosts or {}) do
        if host.x and host.z then
          local px,py=world_to_screen(host.x,host.z)
          marker(px,py,host.online and colors.cyan or colors.red,1)
          set_pixel(px,py,colors.white)
        end
      end
      for _,client in ipairs(state.clients or {}) do
        if client.x and client.z then
          local px,py=world_to_screen(client.x,client.z)
          local c=(client.online and client.fix) and colors.lime or colors.orange
          marker(px,py,colors.black,2)
          marker(px,py,c,1)
          set_pixel(px,py,colors.white)
        end
      end
    end
    box:render()
  end

  local function render_text()
    if not monitor then return end
    local w,h=monitor.getSize()
    local stale=not state or (now()-lastReply)>2000
    local ready=state and state.gps_ready==true
    local hostsOnline=state and (state.hosts_online or 0) or 0
    local hostCount=state and (state.host_count or 0) or 0
    local clientsOnline=state and (state.clients_online or 0) or 0
    text_line(1," CCLUA GPS // FACILITY OPERATIONS MAP",colors.white,colors.blue)
    text_line(2,(" GPS %s   HOSTS %d/%d   CLIENTS %d   CTRL %s"):format(
      ready and "READY" or "DEGRADED",hostsOnline,hostCount,clientsOnline,
      stale and "STALE" or "LINK"),ready and colors.lime or colors.orange,colors.black)
    text_line(3,(" CENTER X%d Z%d  R%d   ROT %03d   %.1fHz"):format(
      mapCenterX,mapCenterZ,mapRadius,rotation,1/pollSeconds),colors.lightBlue,colors.black)

    local sidebarW=math.max(27,math.min(34,math.floor(w*0.30)))
    local sideX=w-sidebarW+1
    for y=4,h-2 do
      monitor.setCursorPos(sideX,y)
      monitor.setBackgroundColor(colors.black)
      monitor.write(string.rep(" ",sidebarW))
    end

    local sy=4
    monitor.setCursorPos(sideX,sy); monitor.setTextColor(colors.cyan); monitor.write("MOBILE CLIENT")
    sy=sy+1
    local client=state and state.clients and state.clients[1]
    if client then
      monitor.setCursorPos(sideX,sy); monitor.setTextColor((client.online and client.fix) and colors.lime or colors.orange)
      monitor.write(("ID %-3s %-18s"):format(tostring(client.id or "?"),tostring(client.label or "?")):sub(1,sidebarW))
      sy=sy+1
      monitor.setCursorPos(sideX,sy); monitor.setTextColor(colors.white)
      monitor.write(("X %8.2f  Y %7.2f"):format(client.x or 0,client.y or 0):sub(1,sidebarW))
      sy=sy+1
      monitor.setCursorPos(sideX,sy); monitor.write(("Z %8.2f  %5.1f Hz"):format(client.z or 0,client.rate_hz or 0):sub(1,sidebarW))
      sy=sy+1
      monitor.setCursorPos(sideX,sy); monitor.setTextColor(colors.lightGray)
      monitor.write(("SEQ %-7s MISS %-4s"):format(tostring(client.seq or 0),tostring(client.misses or 0)):sub(1,sidebarW))
      sy=sy+2
    else
      monitor.setCursorPos(sideX,sy); monitor.setTextColor(colors.gray); monitor.write("NO MOBILE CLIENT")
      sy=sy+2
    end
    monitor.setCursorPos(sideX,sy); monitor.setTextColor(colors.cyan); monitor.write("GPS HOSTS")
    sy=sy+1
    for _,host in ipairs(state and state.hosts or {}) do
      if sy>h-3 then break end
      monitor.setCursorPos(sideX,sy)
      monitor.setTextColor(host.online and colors.lime or colors.red)
      monitor.write(("%s %-20s"):format(host.online and "[+]" or "[!]",
        tostring(host.label or ("ID"..tostring(host.id)))):sub(1,sidebarW))
      sy=sy+1
    end

    text_line(h-1," FACILITY=GRAY  EDGE=LIGHT  CYAN=HOST  GREEN=CLIENT  TRAIL=GRAY",colors.gray,colors.black)
    text_line(h,(" CONTROL %d | %s | %dx%d chars -> %dx%d map pixels"):format(
      controlId,tostring(monitorName or "monitor"),w,h,
      box and box.width or 0,box and box.height or 0),colors.gray,colors.black)
  end

  local function render()
    if not monitor then choose_monitor() end
    if not monitor or not box then return end
    update_trails()
    local ok,err=pcall(function()
      render_map()
      render_text()
    end)
    if not ok then
      ctx.kernel.log.write("warning","gps-monitor","facility map render failed",
        {error=tostring(err)},ctx.process.pid)
      monitor=nil
      box=nil
    end
  end

  local function request()
    rednet.send(controlId,{protocol=protocol,op="status"},protocol)
  end

  net.open_management_modems()
  load_terrain()
  choose_monitor()
  ctx.unit.details={
    protocol=protocol,control_id=controlId,monitor=monitorName,
    poll_seconds=pollSeconds,map_center={x=mapCenterX,z=mapCenterZ},
    map_radius=mapRadius,invert_x=invertX,invert_y=invertY,
    terrain=terrain and terrainPath or "missing",renderer="pixelbox-schematic-2x3",rotation=rotation
  }
  ctx.kernel.log.write("info","gps-monitor","GPS facility operations map online",
    ctx.unit.details,ctx.process.pid)

  request()
  render()
  local poll=os.startTimer(pollSeconds)
  while true do
    local ev,a,b,c=coroutine.yield("wait_event")
    if ev=="timer" and a==poll then
      request()
      if not state or (now()-lastReply)>1000 then render_text() end
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
