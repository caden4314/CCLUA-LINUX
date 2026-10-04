return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local net=dofile("/usr/lib/cclua/net.lua")
  local machine=config.machine()
  local protocol="cclua-fleet-v1"
  local managerId=tonumber(machine.manager_computer_id) or 0
  local pollSeconds=tonumber(machine.fleet_poll_seconds) or 1
  local monitor=nil
  local monitorName=nil
  local cache={}
  local snapshot={nodes={}}
  local lastReply=0
  local lastError=nil

  local function now()
    return os.epoch and os.epoch("utc") or 0
  end

  local function choose_monitor()
    local preferred=machine.monitor_side
    if preferred and peripheral.getType(preferred)=="monitor" then
      monitorName=preferred
      monitor=peripheral.wrap(preferred)
    else
      monitorName=nil
      monitor=peripheral.find("monitor",function(name,obj)
        if not monitorName then
          monitorName=name
          return true
        end
        return false
      end)
    end
    if monitor then
      pcall(monitor.setTextScale,tonumber(machine.monitor_text_scale) or 0.5)
      pcall(monitor.setCursorBlink,false)
      pcall(monitor.setBackgroundColor,colors.black)
      pcall(monitor.setTextColor,colors.white)
      pcall(monitor.clear)
      cache={}
    end
    return monitor
  end

  local function worker_defs()
    local defs=machine.fleet_workers
    if type(defs)=="table" and #defs>0 then return defs end
    return {
      {id=7,hostname="serverr-0",label="ServerR_0"},
      {id=8,hostname="serverr-1",label="ServerR_1"},
      {id=6,hostname="serverr-2",label="ServerR_2"},
      {id=9,hostname="serverr-3",label="ServerR_3"},
      {id=4,hostname="serverr-4",label="ServerR_4"},
      {id=10,hostname="serverr-5",label="ServerR_5"},
      {id=5,hostname="serverr-6",label="ServerR_6"},
      {id=11,hostname="serverr-7",label="ServerR_7"},
    }
  end

  local function node_map()
    local out={}
    for _,n in ipairs(snapshot.nodes or {}) do
      if n.id then out[tonumber(n.id)]=n end
      if n.hostname then out[tostring(n.hostname):lower()]=n end
    end
    return out
  end

  local function node_for(def,map)
    return map[tonumber(def.id)] or map[tostring(def.hostname or ""):lower()]
  end

  local function age_seconds(node)
    if not node or not node.last_seen then return math.huge end
    return math.max(0,(now()-tonumber(node.last_seen or 0))/1000)
  end

  local function online(node)
    return age_seconds(node)<8
  end

  local function status_color(state,isOnline)
    if not isOnline then return colors.red end
    state=tostring(state or "BOOTING"):upper()
    if state=="HEALTHY" or state=="CURRENT" then return colors.lime end
    if state=="UPDATING" or state=="BOOTING" or state=="CHECKING" or
       state=="DOWNLOADING" or state=="STAGING" or state=="VERIFYING" or
       state=="READY" or state=="ACTIVATING" then return colors.yellow end
    if state=="DEGRADED" or state=="FAILED" or state=="OFFLINE" then return colors.red end
    return colors.lightGray
  end

  local function pad(s,w)
    s=tostring(s or "")
    if #s>w then return s:sub(1,w) end
    return s..string.rep(" ",math.max(0,w-#s))
  end

  local function line(y,text,fg,bg)
    if not monitor then return end
    local w,h=monitor.getSize()
    if y<1 or y>h then return end
    text=pad(text,w)
    local key=text.."|"..tostring(fg).."|"..tostring(bg)
    if cache[y]==key then return end
    monitor.setCursorPos(1,y)
    monitor.setTextColor(fg or colors.white)
    monitor.setBackgroundColor(bg or colors.black)
    monitor.write(text)
    cache[y]=key
  end

  local function segment(y,x,width,text,fg,bg)
    if not monitor then return end
    local w,h=monitor.getSize()
    if y<1 or y>h or x>w or width<=0 then return end
    width=math.min(width,w-x+1)
    text=pad(text,width)
    -- Segments deliberately bypass line cache; compact card mode redraws only
    -- on new fleet snapshots, not on a high-frequency paint loop.
    monitor.setCursorPos(x,y)
    monitor.setTextColor(fg or colors.white)
    monitor.setBackgroundColor(bg or colors.black)
    monitor.write(text)
  end

  local function display_name(def,node)
    return tostring((def and def.label) or (node and node.hostname) or ("ID "..tostring(def and def.id or "?")))
  end

  local function draw_list(defs,map,w,h)
    local y=4
    line(3,"NODE        STATUS      UPDATE       PROC SVC  AGE",colors.cyan,colors.black)
    for _,def in ipairs(defs) do
      if y>h-2 then break end
      local n=node_for(def,map)
      local st=n and n.status or {}
      local upd=st.update or {}
      local isOn=online(n)
      local state=isOn and tostring(st.system_state or "BOOTING") or "OFFLINE"
      local ustate=isOn and tostring(upd.state or "CHECKING") or "-"
      local pct=tonumber(upd.percent or (ustate=="CURRENT" and 100 or 0)) or 0
      local age=isOn and string.format("%.1fs",age_seconds(n)) or "--"
      local row=("%-11s %-11s %-10s %3d%%  %4s %3s %5s"):format(
        display_name(def,n),state,ustate,pct,
        tostring(st.processes or "-"),tostring(st.services or "-"),age
      )
      line(y,row,status_color(state,isOn),colors.black)
      y=y+1
    end
  end

  local function draw_cards(defs,map,w,h)
    local cols=2
    local gap=2
    local colW=math.floor((w-gap)/cols)
    local cardH=5
    local startY=4

    -- Clear cached full lines because card mode uses partial segments.
    cache={}

    for i,def in ipairs(defs) do
      local col=(i-1)%2
      local row=math.floor((i-1)/2)
      local x=1+col*(colW+gap)
      local y=startY+row*(cardH+1)
      if y+cardH-1>h-1 then break end

      local n=node_for(def,map)
      local st=n and n.status or {}
      local upd=st.update or {}
      local isOn=online(n)
      local state=isOn and tostring(st.system_state or "BOOTING") or "OFFLINE"
      local ustate=isOn and tostring(upd.state or "CHECKING") or "-"
      local pct=tonumber(upd.percent or (ustate=="CURRENT" and 100 or 0)) or 0
      local fg=status_color(state,isOn)
      local headerBg=isOn and colors.gray or colors.red

      segment(y,x,colW,display_name(def,n).."  ID "..tostring(def.id),colors.white,headerBg)
      segment(y+1,x,colW,("%-11s  %-11s"):format(state,ustate),fg,colors.black)
      segment(y+2,x,colW,("Update %3d%%   proc %-3s svc %-3s"):format(
        pct,tostring(st.processes or "-"),tostring(st.services or "-")
      ),colors.lightGray,colors.black)
      segment(y+3,x,colW,("Image %-8s  age %s"):format(
        tostring(upd.current_commit or st.current_commit or "-"):sub(1,8),
        isOn and string.format("%.1fs",age_seconds(n)) or "--"
      ),colors.gray,colors.black)
      local workload=(tonumber(st.processes or 0) or 0)>0 and "WORKLOAD ACTIVE" or "IDLE"
      segment(y+4,x,colW,workload,colors.lightGray,colors.black)
    end
  end

  local function render()
    if not monitor then choose_monitor() end
    if not monitor then return end
    local ok,err=pcall(function()
      local w,h=monitor.getSize()
      local defs=worker_defs()
      local map=node_map()
      local onlineCount,faults=0,0

      for _,def in ipairs(defs) do
        local n=node_for(def,map)
        local isOn=online(n)
        if isOn then onlineCount=onlineCount+1 end
        local st=n and n.status or {}
        local state=tostring(st.system_state or "BOOTING"):upper()
        local upd=tostring((st.update or {}).state or "CHECKING"):upper()
        if not isOn or state=="DEGRADED" or state=="FAILED" or upd=="FAILED" or upd=="OFFLINE" then
          faults=faults+1
        end
      end

      line(1,"CCLUA SERVER ROOM FLEET",colors.white,colors.blue)
      local manager=snapshot.manager or {}
      line(2,("%d/%d ONLINE   %d FAULTS   IMG %s   MGR %s"):format(
        onlineCount,#defs,faults,
        tostring(manager.installedCommit or manager.commit or "-"):sub(1,8),
        tostring(manager.managerState or "CHECKING")
      ),faults>0 and colors.yellow or colors.lime,colors.black)

      if w>=70 and h>=26 then
        draw_cards(defs,map,w,h)
      else
        draw_list(defs,map,w,h)
      end

      local stale=(now()-lastReply)>5000
      line(h,stale and "MANAGER LINK STALE" or
        ("Auto-updates | "..tostring(machine.hostname or "serverr-monitor").." | "..tostring(monitorName or "monitor")),
        stale and colors.red or colors.gray,colors.black)
    end)
    if not ok then
      lastError=tostring(err)
      ctx.kernel.log.write("warning","server-room-monitor","draw failed",{error=lastError},ctx.process.pid)
      choose_monitor()
    end
  end

  local function request_snapshot()
    local ok=rednet.send(managerId,{
      protocol=protocol,
      op="fleet_status",
      hostname=machine.hostname,
      role=machine.role
    },protocol)
    if not ok then lastError="manager send failed" end
  end

  net.open_management_modems()
  choose_monitor()
  ctx.unit.details={protocol=protocol,manager_id=managerId,monitor=monitorName}
  ctx.kernel.log.write("info","server-room-monitor","fleet monitor online",ctx.unit.details,ctx.process.pid)

  request_snapshot()
  render()

  local poll=os.startTimer(pollSeconds)
  local refresh=os.startTimer(1)

  while true do
    local ev,a,b,c=coroutine.yield("wait_event",{"timer","rednet_message","peripheral","peripheral_detach","monitor_resize","terminate"})
    if ev=="timer" and a==poll then
      request_snapshot()
      poll=os.startTimer(pollSeconds)
    elseif ev=="timer" and a==refresh then
      render()
      refresh=os.startTimer(1)
    elseif ev=="rednet_message" and a==managerId and c==protocol and type(b)=="table" then
      if b.protocol==protocol and b.op=="fleet_status" and b.ok and type(b.snapshot)=="table" then
        snapshot=b.snapshot
        lastReply=now()
        lastError=nil
        render()
      end
    elseif ev=="peripheral" or ev=="peripheral_detach" or ev=="monitor_resize" then
      net.open_management_modems()
      choose_monitor()
      render()
    elseif ev=="terminate" then
      return 0
    end
  end
end
