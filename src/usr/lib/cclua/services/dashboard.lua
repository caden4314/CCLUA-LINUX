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
    if state=="HEALTHY" or state=="CURRENT" then return colors.lime end
    if state=="UPDATING" or state=="BOOTING" or state=="CHECKING" or state=="DOWNLOADING" or state=="STAGING" or state=="VERIFYING" or state=="READY" or state=="ACTIVATING" or state=="AVAILABLE" then return colors.yellow end
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
    local git=read("/var/lib/cclua/github/state.json",{})
    local mgr=read("/var/lib/cclua/manager-state.json",{})
    local peers=read("/var/lib/cclua/manager-peers.json",{nodes={}})
    local net=read("/var/lib/cclua/network.json",{peers={},stats={}})

    local function progress_bar(y,current,total)
      if y<1 or y>h then return end
      local width=math.max(8,w-4)
      local pct=total and total>0 and math.max(0,math.min(1,current/total)) or 0
      local filled=math.floor(width*pct+0.5)
      monitor.setCursorPos(3,y)
      monitor.setBackgroundColor(colors.gray)
      monitor.write(string.rep(" ",width))
      if filled>0 then
        monitor.setCursorPos(3,y)
        monitor.setBackgroundColor(colors.lime)
        monitor.write(string.rep(" ",filled))
      end
      monitor.setBackgroundColor(colors.black)
    end

    draw_header("CCLUA NETWORK SERVER | "..(machine.hostname or "linux-network"))
    text(2,4,"SYSTEM",colors.cyan)
    text(10,4,"["..tostring(status.state or "UNKNOWN").."]",status_color(status.state))
    text(2,5,("Role       %s"):format(machine.role or "network-manager"),colors.lightGray)
    text(2,6,("Installed  %s"):format(tostring(mgr.installed_commit or "-"):sub(1,12)),colors.lightGray)
    text(2,7,("Available  %s"):format(tostring(mgr.image_commit or git.imageCommit or git.commit or "-"):sub(1,12)),colors.lightGray)
    text(2,8,("Slot       %s   files %s"):format(mgr.active_slot or git.activeSlot or "-",mgr.files or git.files or "-"),colors.lightGray)

    text(2,10,"GITHUB UPDATE",colors.cyan)
    local phase=mgr.state or "STARTING"
    text(16,10,"["..tostring(phase).."]",status_color(phase))
    text(2,11,("Repo       %s"):format(mgr.repo or "caden4314/CCLUA-LINUX"),colors.lightGray)
    text(2,12,("Ref        %s"):format(mgr.ref or git.ref or machine.channel or "main"),colors.lightGray)

    local busy=phase=="CHECKING" or phase=="DOWNLOADING" or phase=="STAGING" or phase=="VERIFYING" or phase=="ACTIVATING"
    if busy then
      text(2,13,("%-10s %s"):format(tostring(mgr.current_action or "WORK"),clipped(mgr.current_file or "repository",w-14)),colors.yellow)
      progress_bar(14,mgr.progress or 0,mgr.total or 0)
      local pct=(mgr.total or 0)>0 and math.floor(((mgr.progress or 0)/(mgr.total or 1))*100) or 0
      text(2,15,("Progress   %s/%s  %d%%"):format(mgr.progress or 0,mgr.total or 0,pct),colors.lightGray)
    else
      text(2,13,("Last check %s"):format(mgr.last_check or "-"),colors.lightGray)
    end

    local d=mgr.delta or git.lastDelta or {}
    text(2,16,("Delta      +%d  ~%d  -%d  =%d"):format(
      d.added or 0,d.changed or 0,d.removed or 0,d.unchanged or 0
    ),colors.lightGray)
    if mgr.last_error then text(2,17,"Error      "..tostring(mgr.last_error),colors.red) end

    local nodesY=mgr.last_error and 19 or 18
    if nodesY<=h-2 then
      text(2,nodesY,"FLEET",colors.cyan)
      local y=nodesY+1
      local nodes=peers.nodes or {}
      if #nodes==0 and net.peers then nodes=net.peers end
      if #nodes==0 then
        text(2,y,"Waiting for Ubuntu Server nodes...",colors.orange)
      else
        local now=os.epoch and os.epoch("utc") or 0
        for _,peer in ipairs(nodes) do
          if y>h-1 then break end
          local last=peer.last_seen or peer.last_message or 0
          local age=math.max(0,(now-last)/1000)
          local online=age<10
          local st=peer.status or {}
          text(2,y,(online and "[+] " or "[!] ")..
            clipped(peer.hostname or ("node-"..tostring(peer.id)),math.max(10,math.floor(w*0.34))),
            online and colors.lime or colors.red)
          text(math.floor(w*0.38),y,
            ("ID %-3s %-10s svc %-2s age %.0fs"):format(
              tostring(peer.id or "-"),tostring(peer.role or st.role or "server"),
              tostring(st.services or "-"),age
            ),colors.lightGray)
          y=y+1
        end
      end
    end

    text(2,h,"Ubuntu Server + CCLUA managerd | "..tostring(monitorName or "monitor"),colors.lightBlue)
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
          if machine.role=="manager" or machine.role=="network-manager" then draw_manager() else draw_server() end
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