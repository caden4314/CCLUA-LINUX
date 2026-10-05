return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local monitorLayout=dofile("/usr/lib/cclua/monitor_layout.lua")
  local machine=config.machine()
  local monitor=nil
  local monitorName=nil

  local function choose_monitor()
    local preferred=machine.monitor_side
    if preferred and peripheral.getType(preferred)=="monitor" then
      monitorName=preferred
      monitor=peripheral.wrap(preferred)
    elseif preferred and machine.monitor_strict==true then
      monitorName=nil
      monitor=nil
    else
      monitorName=nil
      monitor=peripheral.find("monitor",function(name)
        if not monitorName then monitorName=name end
        return true
      end)
    end
    if monitor then
      local fit=monitorLayout.configure(monitor,machine,{
        min_width=46,
        min_height=18,
        max_scale=3.0,
      })
      ctx.unit.details=ctx.unit.details or {}
      ctx.unit.details.monitor_scale=fit.scale
      ctx.unit.details.monitor_width=fit.width
      ctx.unit.details.monitor_height=fit.height
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
    state=tostring(state or "BOOTING"):upper()
    if state=="HEALTHY" or state=="CURRENT" or state=="ONLINE" or state=="PASSED" then return colors.lime end
    if state=="UPDATING" or state=="BOOTING" or state=="CHECKING" or state=="DOWNLOADING" or state=="STAGING" or state=="VERIFYING" or state=="READY" or state=="ACTIVATING" or state=="AVAILABLE" then return colors.yellow end
    if state=="DEGRADED" or state=="FAILED" or state=="ROLLBACK" or state=="OFFLINE" or state=="NO_MODEM" then return colors.red end
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
    text(2,2,clipped(("Ubuntu 22.04.5 | ID %d | %s | %s"):format(
      os.getComputerID(),tostring(machine.role or "server"),tostring(machine.address or "-")
    ),w-2),colors.white,colors.gray)
  end

  local function draw_server_compact()
    local w,h=size()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    local status=read("/var/lib/cclua/status.json",{state="BOOTING"})
    local post=read("/var/lib/cclua/post.json",{state="UNKNOWN"})
    local link=read("/var/lib/cclua/network-health.json",{state="CHECKING"})
    local update=read("/var/lib/cclua/update-state.json",{})
    local net=read("/var/lib/cclua/network.json",{peers={},stats={}})
    local active,failed,total=service_counts()

    fill(1,colors.blue)
    text(2,1,clipped((machine.hostname or "server").." | "..(machine.role or "server"),w-2),colors.white,colors.blue)
    fill(2,colors.gray)
    text(2,2,("Ubuntu 22.04.5 | ID %d"):format(os.getComputerID()),colors.white,colors.gray)

    text(2,4,"SYSTEM",colors.cyan)
    text(10,4,"["..tostring(status.state or "BOOTING").."]",status_color(status.state))
    text(2,5,("Up %ds  P %d  S %d/%d"):format(
      math.floor(os.clock()),#ctx.kernel.process.all(),active,total
    ),colors.lightGray)
    local fault=tonumber(status.error_code or 0) or 0
    text(2,6,("Periph %d  Fault %d"):format(count(ctx.kernel.device.devices),fault),
      fault>0 and colors.red or colors.lightGray)
    text(2,7,("POST %-9s Link %-9s"):format(
      tostring(post.state or "UNKNOWN"),tostring(link.state or "CHECKING")
    ),post.fatal and colors.red or post.degraded and colors.yellow or colors.lightGray)

    text(2,8,"NETWORK",colors.cyan)
    text(2,9,clipped(machine.address or "-",w-2),colors.lightGray)
    text(2,10,("Mgr %s  RTT %sms"):format(machine.manager or "-",tostring(link.manager_rtt_ms or "-")),colors.lightGray)
    text(2,11,("Peers %d  RX/TX %s/%s"):format(
      #(net.peers or {}),(net.stats or {}).rx or 0,(net.stats or {}).tx or 0
    ),colors.lightGray)

    local phase=tostring(update.state or update.phase or "IDLE")
    local pct=tonumber(update.percent or (phase=="CURRENT" and 100 or 0)) or 0
    local current=tostring(update.current_commit or "-"):sub(1,8)
    local target=tostring(update.target_commit or update.available_commit or "-"):sub(1,8)

    text(2,13,"UPDATE",colors.cyan)
    text(10,13,phase,status_color(phase))
    text(2,14,("%3d%%  %s"):format(pct,current),colors.lightGray)
    text(2,15,("-> %s"):format(target),colors.lightGray)
    if update.current_action and h>=16 then
      text(2,16,clipped(tostring(update.current_action).." "..tostring(update.current_file or ""),w-2),colors.yellow)
    end

    if h>=18 then
      text(2,18,"CORE SERVICES",colors.cyan)
      local core={
        {"cclua-statusd.service","status"},
        {"cclua-update-agent.service","update"},
        {"systemd-networkd.service","network"},
        {"peripherald.service","periph"},
      }
      local y=19
      for _,entry in ipairs(core) do
        if y>h-1 then break end
        local u=ctx.kernel.services:get(entry[1])
        local st=u and u.state or "missing"
        local mark=st=="active" and "[+]" or (st=="failed" and "[!]" or "[-]")
        local col=st=="active" and colors.lime or (st=="failed" and colors.red or colors.gray)
        text(2,y,("%s %-8s %s"):format(mark,entry[2],st),col)
        y=y+1
      end
    end

    text(2,h,clipped("CCLUA | "..tostring(monitorName or "?"),w-2),colors.gray)
  end

  local function draw_server_wide()
    local w,h=size()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    local status=read("/var/lib/cclua/status.json",{state="BOOTING"})
    local post=read("/var/lib/cclua/post.json",{state="UNKNOWN"})
    local link=read("/var/lib/cclua/network-health.json",{state="CHECKING"})
    local update=read("/var/lib/cclua/update-state.json",{})
    local net=read("/var/lib/cclua/network.json",{peers={},stats={}})
    local active,failed,total=service_counts()
    local fault=tonumber(status.error_code or 0) or 0

    draw_header((machine.hostname or "ubuntu-server").." | server console")
    local gap=2
    local cardW=math.floor((w-4-gap*2)/3)
    local x1=2
    local x2=x1+cardW+gap
    local x3=x2+cardW+gap

    text(x1,4,"SYSTEM",colors.cyan)
    text(x1,5,tostring(status.state or "BOOTING"),status_color(status.state))
    text(x1,6,("%d/%d services"):format(active,total),failed>0 and colors.red or colors.lightGray)
    text(x1,7,("%d processes  up %ds"):format(#ctx.kernel.process.all(),math.floor(os.clock())),colors.lightGray)
    if fault>0 then
      text(x1,8,clipped(("FAULT %d %s"):format(fault,status.error_reason or ""),cardW),colors.red)
    else
      text(x1,8,("POST %s"):format(tostring(post.state or "UNKNOWN")),status_color(post.state))
    end

    text(x2,4,"NETWORK",colors.cyan)
    text(x2,5,tostring(link.state or "CHECKING"),status_color(link.state))
    text(x2,6,clipped("IP "..tostring(machine.address or "-"),cardW),colors.lightGray)
    text(x2,7,("RTT %sms  missed %s"):format(link.manager_rtt_ms or "-",link.missed_probes or 0),colors.lightGray)
    text(x2,8,("Peers %d  modems %s"):format(#(net.peers or {}),link.modem_count or 0),colors.lightGray)

    local phase=tostring(update.state or update.phase or "IDLE")
    local pct=tonumber(update.percent or (phase=="CURRENT" and 100 or 0)) or 0
    text(x3,4,"UPDATE",colors.cyan)
    text(x3,5,phase,status_color(phase))
    text(x3,6,("%3d%%  %s"):format(pct,tostring(update.current_commit or "-"):sub(1,8)),colors.lightGray)
    text(x3,7,"Target "..tostring(update.target_commit or update.available_commit or "-"):sub(1,8),colors.lightGray)
    text(x3,8,update.auto_apply==false and "Auto apply OFF" or "Auto apply ON",
      update.auto_apply==false and colors.yellow or colors.gray)

    text(2,10,"SERVICES",colors.cyan)
    fill(11,colors.gray)
    text(2,11,"UNIT",colors.white,colors.gray)
    text(math.floor(w*0.58),11,"STATE",colors.white,colors.gray)
    text(math.floor(w*0.75),11,"PID",colors.white,colors.gray)
    text(math.floor(w*0.84),11,"RESTARTS",colors.white,colors.gray)

    local services={}
    for _,unit in ipairs(ctx.kernel.services:list()) do
      if not unit.reference or unit.exec then services[#services+1]=unit end
    end
    table.sort(services,function(a,b)
      if a.state=="failed" and b.state~="failed" then return true end
      if b.state=="failed" and a.state~="failed" then return false end
      return tostring(a.name)<tostring(b.name)
    end)

    local yy=12
    for _,unit in ipairs(services) do
      if yy>h-1 then break end
      local color=unit.state=="active" and colors.lime
        or unit.state=="failed" and colors.red or colors.gray
      text(2,yy,clipped(unit.name,math.floor(w*0.54)),color)
      text(math.floor(w*0.58),yy,tostring(unit.state),color)
      text(math.floor(w*0.75),yy,tostring(unit.pid or "-"),colors.lightGray)
      text(math.floor(w*0.84),yy,tostring(unit.total_restarts or 0),
        tonumber(unit.total_restarts or 0)>0 and colors.yellow or colors.gray)
      yy=yy+1
    end

    local footer=failed>0 and ("%d FAILED | systemctl --failed"):format(failed)
      or ("Healthy | "..tostring(monitorName or "monitor").." | cclua-status")
    text(2,h,clipped(footer,w-2),failed>0 and colors.red or colors.gray)
  end

  local function draw_server()
    local w,h=size()
    if w>=70 and h>=26 then
      draw_server_wide()
      return
    end
    if w<46 or h<23 then
      draw_server_compact()
      return
    end
    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    local status=read("/var/lib/cclua/status.json",{state="BOOTING"})
    local post=read("/var/lib/cclua/post.json",{state="UNKNOWN"})
    local link=read("/var/lib/cclua/network-health.json",{state="CHECKING"})
    local update=read("/var/lib/cclua/update-state.json",{})
    local net=read("/var/lib/cclua/network.json",{peers={},stats={}})
    local active,failed,total=service_counts()

    draw_header((machine.hostname or "ubuntu-server").." | "..(machine.role or "server"))

    text(2,4,"SYSTEM STATUS",colors.cyan)
    text(16,4,"["..tostring(status.state or "BOOTING").."]",status_color(status.state))
    text(2,5,("Uptime       %ds"):format(math.floor(os.clock())),colors.lightGray)
    text(2,6,("Processes    %d"):format(#ctx.kernel.process.all()),colors.lightGray)
    text(2,7,("Services     %d/%d active  %d failed"):format(active,total,failed),
      failed>0 and colors.red or colors.lightGray)
    text(2,8,("Peripherals  %d"):format(count(ctx.kernel.device.devices)),colors.lightGray)

    local lampSide=status.lamp_side or machine.status_light_side or "bottom"
    text(2,9,("Status lamp  %s / %s"):format(lampSide,status.lamp_output and "ON" or "OFF"),
      status.lamp_output and colors.red or colors.gray)
    local faultCode=tonumber(status.error_code or 0) or 0
    text(2,10,faultCode>0
      and ("Fault %d     %s"):format(faultCode,clipped(status.error_reason or "fault",w-14))
      or ("POST         %s (%s/%s/%s)"):format(
        tostring(post.state or "UNKNOWN"),post.pass or 0,post.warn or 0,post.fail or 0
      ),
      faultCode>0 and colors.red or (post.degraded and colors.yellow or colors.gray))

    text(2,11,"NETWORK",colors.cyan)
    text(2,12,("Address      %s"):format(machine.address or "-"),colors.lightGray)
    text(2,13,("Manager      %s"):format(machine.manager or "-"),colors.lightGray)
    text(2,14,("Link         %-10s RTT %sms missed %s"):format(
      tostring(link.state or "CHECKING"),tostring(link.manager_rtt_ms or "-"),tostring(link.missed_probes or 0)
    ),status_color(link.state))
    text(2,15,("Peers        %d  modems %s"):format(#(net.peers or {}),tostring(link.modem_count or 0)),colors.lightGray)
    text(2,16,("RX/TX        %s / %s  dup %s"):format(
      (net.stats or {}).rx or 0,(net.stats or {}).tx or 0,(net.stats or {}).duplicates or 0
    ),colors.lightGray)

    if h>=18 then
      text(2,17,"UPDATE",colors.cyan)
      local phase=update.state or update.phase or "IDLE"
      local current=tostring(update.current_commit or "-"):sub(1,8)
      local target=tostring(update.target_commit or update.available_commit or "-"):sub(1,8)
      local pct=tonumber(update.percent or 0) or 0
      text(2,18,("State        %-12s %3d%%"):format(phase,pct),status_color(phase))
      if h>=19 then text(2,19,("Image        %s -> %s"):format(current,target),colors.lightGray) end
      if h>=20 and update.current_action then
        text(2,20,("%-12s %s"):format(tostring(update.current_action),clipped(update.current_file or "",w-15)),colors.yellow)
      end
      if h>=21 and update.last_result then
        text(2,21,("Last         %s"):format(clipped(update.last_result,w-15)),colors.gray)
      end
    end

    local listStart=h>=27 and 23 or 17
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
    local post=read("/var/lib/cclua/post.json",{state="UNKNOWN"})
    local link=read("/var/lib/cclua/network-health.json",{state="CHECKING"})
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
    text(10,4,"["..tostring(status.state or "BOOTING").."]",status_color(status.state))
    text(2,5,("Role       %s"):format(machine.role or "network-manager"),colors.lightGray)
    text(2,6,("Installed  %s"):format(tostring(mgr.installed_commit or "-"):sub(1,12)),colors.lightGray)
    text(2,7,("Available  %s"):format(tostring(mgr.image_commit or git.imageCommit or git.commit or "-"):sub(1,12)),colors.lightGray)
    text(2,8,("Slot       %s   files %s"):format(mgr.active_slot or git.activeSlot or "-",mgr.files or git.files or "-"),colors.lightGray)
    text(2,9,("POST %-9s  NET %-9s modems %s"):format(
      tostring(post.state or "UNKNOWN"),tostring(link.state or "CHECKING"),tostring(link.modem_count or 0)
    ),post.fatal and colors.red or post.degraded and colors.yellow or colors.lightGray)
    local managerFault=tonumber(status.error_code or 0) or 0
    if managerFault>0 then
      text(math.floor(w*0.55),4,("FAULT %d"):format(managerFault),colors.red)
      text(math.floor(w*0.55),5,clipped(status.error_reason or "system fault",math.floor(w*0.45)),colors.red)
    end

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
          local upd=st.update or {}
          local updState=tostring(upd.state or "CHECKING")
          local updPct=tonumber(upd.percent or (updState=="CURRENT" and 100 or 0)) or 0
          text(2,y,(online and "[+] " or "[!] ")..
            clipped(peer.hostname or ("node-"..tostring(peer.id)),math.max(10,math.floor(w*0.30))),
            online and colors.lime or colors.red)
          text(math.floor(w*0.33),y,
            ("ID %-3s %-11s %3d%% age %.0fs"):format(
              tostring(peer.id or "-"),clipped(updState,11),updPct,age
            ),status_color(updState))
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
    local w,h=monitor.getSize()
    ctx.kernel.log.write("info","dashboard","monitor dashboard online",{
      monitor=monitorName,width=w,height=h,
      layout=(w<46 or h<23) and "compact" or "full"
    },ctx.process.pid)
  end

  local timer=os.startTimer(0.2)
  while true do
    local ev,a=coroutine.yield("wait_event",{"timer","monitor_resize","peripheral","peripheral_detach"})
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