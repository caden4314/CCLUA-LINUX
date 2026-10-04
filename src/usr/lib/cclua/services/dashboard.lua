return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local machine=config.machine()
  local monitor=nil
  local monitorName=nil

  local function choose_monitor()
    local preferred=machine.monitor_side
    if preferred and peripheral.getType(preferred)=="monitor" then
      monitorName=preferred
      monitor=peripheral.wrap(preferred)
    else
      monitorName=nil
      monitor=peripheral.find("monitor",function(name)
        if not monitorName then monitorName=name end
        return true
      end)
    end
    if monitor then
      pcall(monitor.setTextScale,tonumber(machine.monitor_text_scale) or 0.5)
      pcall(monitor.setBackgroundColor,colors.black)
      pcall(monitor.setTextColor,colors.white)
    end
    return monitor
  end

  local function read(path,default)
    return config.read_json(path,default)
  end

  local function count(t)
    local n=0
    for _ in pairs(t or {}) do n=n+1 end
    return n
  end

  local function clipped(s,n)
    s=tostring(s or "")
    if n<=0 then return "" end
    if #s>n then
      if n<=3 then return s:sub(1,n) end
      return s:sub(1,n-3).."..."
    end
    return s
  end

  local function size()
    if not monitor then return 0,0 end
    return monitor.getSize()
  end

  local function fill(y,bg)
    local w=size()
    monitor.setCursorPos(1,y)
    monitor.setBackgroundColor(bg)
    monitor.write(string.rep(" ",w))
  end

  local function text(x,y,s,fg,bg)
    local w,h=size()
    if y<1 or y>h or x>w then return end
    monitor.setCursorPos(math.max(1,x),y)
    monitor.setTextColor(fg or colors.white)
    monitor.setBackgroundColor(bg or colors.black)
    monitor.write(clipped(s,w-math.max(1,x)+1))
  end

  local function status_color(state)
    state=tostring(state or "UNKNOWN"):upper()
    if state=="HEALTHY" then return colors.lime end
    if state=="UPDATING" or state=="BOOTING" then return colors.yellow end
    if state=="DEGRADED" or state=="FAILED" or state=="ROLLBACK" then return colors.red end
    return colors.lightGray
  end

  local function service_counts()
    local active,failed,total=0,0,0
    for _,u in ipairs(ctx.kernel.services:list()) do
      if not u.reference or u.exec then
        total=total+1
        if u.state=="active" then active=active+1 end
        if u.state=="failed" then failed=failed+1 end
      end
    end
    return active,failed,total
  end

  local function draw_header(title)
    local w=size()
    fill(1,colors.blue)
    text(2,1,clipped(title,w-2),colors.white,colors.blue)
    fill(2,colors.gray)
    text(2,2,("Ubuntu 22.04.5 LTS | kernel %s | ID %d"):format(
      tostring(ctx.kernel.version.version),
      os.getComputerID()
    ),colors.white,colors.gray)
  end

  local function draw_server()
    local w,h=size()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    local status=read("/var/lib/cclua/status.json",{state="BOOTING"})
    local update=read("/var/lib/cclua/update-state.json",{})
    local net=read("/var/lib/cclua/network.json",{peers={},stats={}})
    local active,failed,total=service_counts()

    draw_header((machine.hostname or "ubuntu-server").." | "..(machine.role or "server"))

    text(2,4,"SYSTEM STATUS",colors.cyan)
    text(16,4,"["..tostring(status.state or "UNKNOWN").."]",status_color(status.state))
    text(2,5,("Uptime       %ds"):format(math.floor(os.clock())),colors.lightGray)
    text(2,6,("Processes    %d"):format(#ctx.kernel.process.all()),colors.lightGray)
    text(2,7,("Services     %d/%d active  %d failed"):format(active,total,failed),
      failed>0 and colors.red or colors.lightGray)
    text(2,8,("Peripherals  %d"):format(count(ctx.kernel.device.devices)),colors.lightGray)

    local lampSide=status.lamp_side or machine.status_light_side or "bottom"
    text(2,9,("Status lamp  %s / %s"):format(lampSide,status.lamp_output and "ON" or "OFF"),
      status.lamp_output and colors.lime or colors.gray)

    text(2,11,"NETWORK",colors.cyan)
    text(2,12,("Address      %s"):format(machine.address or "-"),colors.lightGray)
    text(2,13,("Manager      %s"):format(machine.manager or "-"),colors.lightGray)
    text(2,14,("Peers        %d"):format(#(net.peers or {})),colors.lightGray)
    text(2,15,("RX/TX        %s / %s"):format((net.stats or {}).rx or 0,(net.stats or {}).tx or 0),colors.lightGray)

    if h>=18 then
      text(2,17,"UPDATE",colors.cyan)
      local phase=update.state or update.phase or "IDLE"
      local build=update.commit or update.build or update.version or "-"
      text(2,18,("State        %s"):format(phase),status_color(phase))
      if h>=19 then text(2,19,("Build        %s"):format(clipped(build,w-15)),colors.lightGray) end
    end

    local listStart=h>=25 and 21 or 17
    if h>=listStart+2 then
      text(math.floor(w/2)+1,4,"SERVICES",colors.cyan)
      local y=5
      for _,u in ipairs(ctx.kernel.services:list()) do
        if y>h-1 then break end
        if not u.reference or u.exec then
          local c=u.state=="active" and colors.lime or (u.state=="failed" and colors.red or colors.gray)
          local mark=u.state=="active" and "[+]" or (u.state=="failed" and "[!]" or "[-]")
          text(math.floor(w/2)+1,y,mark.." "..u.name,c)
          y=y+1
        end
      end
    end

    text(2,h,"CCLUA Ubuntu Server | monitor "..tostring(monitorName or "?"),colors.gray)
  end

  local function draw_manager()
    local w,h=size()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    local status=read("/var/lib/cclua/status.json",{state="BOOTING"})
    local net=read("/var/lib/cclua/network.json",{peers={},stats={}})
    local git=read("/var/lib/cclua/github/state.json",{})

    draw_header("CCLUA CLUSTER MANAGER | "..(machine.hostname or "manager"))
    text(2,4,"MANAGER",colors.cyan)
    text(12,4,"["..tostring(status.state or "UNKNOWN").."]",status_color(status.state))
    text(2,5,("Address  %s"):format(machine.address or "-"),colors.lightGray)
    text(2,6,("Git ref  %s"):format(git.ref or machine.channel or "-"),colors.lightGray)
    text(2,7,("Commit   %s"):format(tostring(git.commit or "-"):sub(1,12)),colors.lightGray)
    text(2,8,("Slot     %s  files %s"):format(git.activeSlot or "-",git.files or "-"),colors.lightGray)

    text(2,10,"NODES",colors.cyan)
    local y=11
    if #(net.peers or {})==0 then
      text(2,y,"Waiting for node heartbeats...",colors.orange)
    else
      for _,peer in ipairs(net.peers or {}) do
        if y>h-2 then break end
        local age=math.max(0,((os.epoch("utc")-(peer.last_message or 0))/1000))
        local online=age<8
        local c=online and colors.lime or colors.red
        local st=peer.status or {}
        text(2,y,(online and "[+] " or "[!] ")..
          clipped((peer.hostname or ("node-"..tostring(peer.id))),math.max(10,math.floor(w*0.38))),c)
        text(math.floor(w*0.42),y,
          ("ID %-3s svc %-2s proc %-2s age %.0fs"):format(
            tostring(peer.id),tostring(st.services or "-"),
            tostring(st.processes or "-"),age
          ),colors.lightGray)
        y=y+1
      end
    end

    if h>=y+2 then
      text(2,h-1,("Network RX/TX %s/%s | peers %d"):format(
        (net.stats or {}).rx or 0,(net.stats or {}).tx or 0,#(net.peers or {})
      ),colors.gray)
    end
    text(2,h,"CCLUA Network Manager",colors.lightBlue)
  end

  choose_monitor()
  if not monitor then
    ctx.kernel.log.write("warning","dashboard","no monitor attached; waiting for hotplug",nil,ctx.process.pid)
  else
    ctx.kernel.log.write("info","dashboard","monitor dashboard online",{monitor=monitorName},ctx.process.pid)
  end

  local timer=os.startTimer(0.2)
  while true do
    local ev,a=coroutine.yield("wait_event")
    if ev=="timer" and a==timer then
      if monitor then
        local ok,err=pcall(function()
          if machine.role=="manager" then draw_manager() else draw_server() end
        end)
        if not ok then
          ctx.kernel.log.write("warning","dashboard","draw failed",{error=tostring(err)},ctx.process.pid)
          choose_monitor()
        end
      end
      timer=os.startTimer(1)
    elseif ev=="monitor_resize" or ev=="peripheral" or ev=="peripheral_detach" then
      choose_monitor()
    end
  end
end
