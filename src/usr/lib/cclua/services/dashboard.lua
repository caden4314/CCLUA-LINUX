return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local machine=config.machine()

  local mon=peripheral.find("monitor")
  if not mon then
    ctx.kernel.log.write("warning","dashboard","no monitor attached",nil,ctx.process.pid)
    while true do coroutine.yield("wait_event","peripheral") end
  end

  mon.setTextScale(0.5)
  local function size() return mon.getSize() end
  local function fill(y,bg)
    local w=size()
    mon.setCursorPos(1,y)
    mon.setBackgroundColor(bg)
    mon.write(string.rep(" ",w))
  end
  local function text(x,y,s,fg,bg)
    mon.setCursorPos(x,y)
    mon.setTextColor(fg or colors.white)
    mon.setBackgroundColor(bg or colors.black)
    mon.write(tostring(s))
  end
  local function clipped(s,n)
    s=tostring(s or "")
    if #s>n then return s:sub(1,math.max(0,n-3)).."..." end
    return s
  end
  local function count(t) local n=0 for _ in pairs(t or {}) do n=n+1 end return n end

  local function draw_header(title)
    local w=size()
    fill(1,colors.blue)
    text(2,1,clipped(title,w-2),colors.white,colors.blue)
    fill(2,colors.gray)
    text(2,2,("Ubuntu 22.04.5 LTS  -  Kernel %s"):format(ctx.kernel.version.version),colors.white,colors.gray)
  end

  local function draw_server()
    local w,h=size()
    mon.setBackgroundColor(colors.black)
    mon.clear()
    draw_header((machine.hostname or "server").."  ["..(machine.address or "?").."]")

    local active=0
    for _,u in ipairs(ctx.kernel.services:list()) do if u.state=="active" then active=active+1 end end
    local proc=#ctx.kernel.process.all()
    local per=count(ctx.kernel.device.devices)
    local net=config.read_json("/var/lib/cclua/network.json",{peers={},stats={}})

    text(2,4,"SYSTEM",colors.cyan)
    text(2,5,("Uptime       %s sec"):format(math.floor(os.clock())),colors.lightGray)
    text(2,6,("Processes    %d"):format(proc),colors.lightGray)
    text(2,7,("Services     %d active"):format(active),colors.lightGray)
    text(2,8,("Peripherals  %d"):format(per),colors.lightGray)

    text(2,10,"NETWORK",colors.cyan)
    text(2,11,("Address      %s"):format(machine.address or "-"),colors.lightGray)
    text(2,12,("Manager      %s"):format(machine.manager or "-"),colors.lightGray)
    text(2,13,("Peers        %d"):format(#(net.peers or {})),colors.lightGray)
    text(2,14,("RX/TX        %s / %s"):format((net.stats or {}).rx or 0,(net.stats or {}).tx or 0),colors.lightGray)

    text(2,16,"SERVICES",colors.cyan)
    local y=17
    for _,u in ipairs(ctx.kernel.services:list()) do
      if y>h then break end
      local c=u.state=="active" and colors.lime or (u.state=="failed" and colors.red or colors.lightGray)
      text(2,y,(u.state=="active" and "[+] " or "[-] ")..clipped(u.name,w-5),c)
      y=y+1
    end
  end

  local function draw_manager()
    local w,h=size()
    mon.setBackgroundColor(colors.black)
    mon.clear()
    draw_header("CCLUA CLUSTER MANAGER  •  "..(machine.address or ""))

    local net=config.read_json("/var/lib/cclua/network.json",{peers={},stats={}})
    text(2,4,"CLUSTER STATUS",colors.cyan)
    text(2,5,("Local: %-14s  ID %d"):format(machine.hostname or "manager",os.getComputerID()),colors.lime)
    text(2,6,("Network RX/TX: %s / %s"):format((net.stats or {}).rx or 0,(net.stats or {}).tx or 0),colors.lightGray)

    local y=8
    local seen={}
    for _,peer in ipairs(net.peers or {}) do
      seen[peer.id]=true
      if y+3>h then break end
      local age=math.max(0,((os.epoch("utc")-(peer.last_message or 0))/1000))
      local online=age<8
      local c=online and colors.lime or colors.red
      text(2,y,(online and "[+] " or "[!] ")..clipped((peer.hostname or ("node-"..tostring(peer.id))),w-5),c)
      text(4,y+1,("ID %-2s  %-12s  age %.1fs"):format(tostring(peer.id),peer.address or "-",age),colors.lightGray)
      if peer.status then
        text(4,y+2,("proc %s  svc %s  per %s"):format(peer.status.processes or "-",peer.status.services or "-",peer.status.peripherals or "-"),colors.gray)
      end
      y=y+4
    end
    if #(net.peers or {})==0 then text(2,9,"Waiting for server heartbeats...",colors.orange) end

    if h>=y+2 then
      text(2,h-1,"SERVER_CYAN  |  SERVER_ORANGE  |  MANAGER",colors.gray)
      text(2,h,"CCLUA NET v2",colors.lightBlue)
    end
  end

  local timer=os.startTimer(0.2)
  while true do
    local ev,a=coroutine.yield("wait_event")
    if ev=="timer" and a==timer then
      if machine.role=="manager" then draw_manager() else draw_server() end
      timer=os.startTimer(1)
    elseif ev=="monitor_resize" or ev=="peripheral" then
      mon=peripheral.find("monitor") or mon
    end
  end
end
