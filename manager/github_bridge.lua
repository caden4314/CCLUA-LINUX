-- CCLUA-LINUX network manager / GitHub bridge
-- LINUX_NETWORK: GitHub authority, A/B source cache, fleet dashboard and status lamp.

local M = {}

local CFG = {
  owner = "caden4314",
  repo = "CCLUA-LINUX",
  ref = "main",
  root = "/var/lib/cclua/github",
  protocol = "cclua-manager-v1",
  pollSeconds = 120,
  statusSide = "bottom",
  monitorScale = 0.5,
}

local runtime = {
  state = "BOOTING",
  progress = 0,
  total = 0,
  lastError = nil,
  lastCheck = nil,
  changed = false,
  nodes = {},
  tick = 0,
}

local monitor, monitorName
local modemName

local function join(a, b)
  if a:sub(-1) == "/" then return a .. b end
  return a .. "/" .. b
end

local function ensureDir(path)
  if path=="" or fs.exists(path) then return end
  local parent = fs.getDir(path)
  if parent ~= "" and not fs.exists(parent) then ensureDir(parent) end
  fs.makeDir(path)
end

local function writeAll(path, data)
  ensureDir(fs.getDir(path))
  local h, err = fs.open(path, "w")
  if not h then return nil, err or "open failed" end
  h.write(data)
  h.close()
  return true
end

local function readAll(path)
  if not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  if not h then return nil end
  local data = h.readAll()
  h.close()
  return data
end

local function loadState()
  local raw = readAll(join(CFG.root, "state.json"))
  if not raw then return { activeSlot = "A" } end
  local ok, state = pcall(textutils.unserializeJSON, raw)
  if not ok or type(state) ~= "table" then return { activeSlot = "A" } end
  state.activeSlot = state.activeSlot == "B" and "B" or "A"
  return state
end

local function saveState(state)
  ensureDir(CFG.root)
  return writeAll(join(CFG.root, "state.json"), textutils.serializeJSON(state))
end

local function chooseMonitor()
  monitorName=nil
  monitor=peripheral.find("monitor",function(name)
    if not monitorName then monitorName=name end
    return true
  end)
  if monitor then
    pcall(monitor.setTextScale,CFG.monitorScale)
    pcall(monitor.setBackgroundColor,colors.black)
    pcall(monitor.setTextColor,colors.white)
  end
  return monitor
end

local function findWirelessModem()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
      local m = peripheral.wrap(name)
      local ok, wireless = pcall(m.isWireless)
      if ok and wireless then return name end
    end
  end
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

local function statusColor(state)
  state=tostring(state or ""):upper()
  if state=="HEALTHY" or state=="CURRENT" then return colors.lime end
  if state=="BOOTING" or state=="CHECKING" or state=="UPDATING" then return colors.yellow end
  if state=="DEGRADED" or state=="FAILED" then return colors.red end
  return colors.lightGray
end

local function setLamp()
  runtime.tick=runtime.tick+1
  local state=runtime.state
  local on
  if state=="HEALTHY" or state=="CURRENT" then
    on=true
  elseif state=="DEGRADED" or state=="FAILED" then
    on=runtime.tick%2==0
  else
    on=math.floor(runtime.tick/2)%2==0
  end
  pcall(redstone.setOutput,CFG.statusSide,on)
  return on
end

local function draw()
  if not monitor then chooseMonitor() end
  if not monitor then return end

  local ok,err=pcall(function()
    local w,h=monitor.getSize()
    local state=loadState()
    local lamp=setLamp()

    local function fill(y,bg)
      if y<1 or y>h then return end
      monitor.setCursorPos(1,y)
      monitor.setBackgroundColor(bg)
      monitor.write(string.rep(" ",w))
    end
    local function text(x,y,s,fg,bg)
      if y<1 or y>h or x>w then return end
      monitor.setCursorPos(math.max(1,x),y)
      monitor.setTextColor(fg or colors.white)
      monitor.setBackgroundColor(bg or colors.black)
      monitor.write(clipped(s,w-math.max(1,x)+1))
    end

    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    fill(1,colors.blue)
    text(2,1,"CCLUA NETWORK MANAGER",colors.white,colors.blue)
    fill(2,colors.gray)
    text(2,2,("LINUX_NETWORK | ID %d | GitHub authority"):format(os.getComputerID()),colors.white,colors.gray)

    text(2,4,"MANAGER STATUS",colors.cyan)
    text(18,4,"["..runtime.state.."]",statusColor(runtime.state))
    text(2,5,("Repo       %s/%s"):format(CFG.owner,CFG.repo),colors.lightGray)
    text(2,6,("Branch     %s"):format(CFG.ref),colors.lightGray)
    text(2,7,("Commit     %s"):format(tostring(state.commit or "-"):sub(1,12)),colors.lightGray)
    text(2,8,("Cache slot %s   %s files   %s KiB"):format(
      state.activeSlot or "-",state.files or "-",
      state.bytes and math.floor(state.bytes/1024) or "-"
    ),colors.lightGray)
    text(2,9,("Lamp       %s / %s"):format(CFG.statusSide,lamp and "ON" or "OFF"),
      lamp and colors.lime or colors.gray)

    text(2,11,"UPDATE",colors.cyan)
    if runtime.total>0 and (runtime.state=="UPDATING" or runtime.state=="CHECKING") then
      local pct=math.floor((runtime.progress/math.max(1,runtime.total))*100)
      text(2,12,("Progress   %d/%d (%d%%)"):format(runtime.progress,runtime.total,pct),colors.yellow)
    else
      text(2,12,("Last check %s"):format(runtime.lastCheck or "-"),colors.lightGray)
    end
    text(2,13,("Result     %s"):format(runtime.changed and "UPDATED" or "CURRENT"),
      runtime.changed and colors.yellow or colors.lime)
    if runtime.lastError then text(2,14,"Error      "..runtime.lastError,colors.red) end

    local networkY=runtime.lastError and 16 or 15
    text(2,networkY,"NETWORK",colors.cyan)
    text(2,networkY+1,("Modem      %s"):format(modemName or "not attached"),
      modemName and colors.lime or colors.orange)
    text(2,networkY+2,("Protocol   %s"):format(CFG.protocol),colors.lightGray)

    local nodesY=networkY+4
    if nodesY<=h-2 then
      text(2,nodesY,"NODES",colors.cyan)
      local y=nodesY+1
      local any=false
      local now=os.epoch and os.epoch("utc") or 0
      local ids={}
      for id in pairs(runtime.nodes) do ids[#ids+1]=id end
      table.sort(ids)
      for _,id in ipairs(ids) do
        if y>h-1 then break end
        any=true
        local n=runtime.nodes[id]
        local age=math.max(0,(now-(n.lastSeen or 0))/1000)
        local online=age<10
        text(2,y,(online and "[+] " or "[!] ")..
          ("ID %s %-16s age %.0fs"):format(id,n.hostname or "node",age),
          online and colors.lime or colors.red)
        y=y+1
      end
      if not any then text(2,y,"Waiting for Ubuntu Server nodes...",colors.orange) end
    end

    text(2,h,"GitHub -> LINUX_NETWORK -> Ubuntu Server",colors.gray)
  end)

  if not ok then
    runtime.lastError="dashboard: "..tostring(err)
    monitor=nil
  end
end

local function setRuntime(state,err)
  runtime.state=state
  runtime.lastError=err
  draw()
end

local function request(url)
  local h, err = http.get(url, {
    ["User-Agent"] = "CCLUA-LINUX/" .. tostring(os.getComputerID()),
    ["Accept"] = "application/vnd.github+json",
    ["X-GitHub-Api-Version"] = "2022-11-28",
  })
  if not h then return nil, err or "HTTP request failed" end
  local code = h.getResponseCode and h.getResponseCode() or 200
  local body = h.readAll()
  h.close()
  if code < 200 or code >= 300 then
    return nil, "HTTP " .. tostring(code) .. ": " .. tostring(body):sub(1, 160)
  end
  return body
end

local function requestJson(url)
  local body, err = request(url)
  if not body then return nil, err end
  local ok, decoded = pcall(textutils.unserializeJSON, body)
  if not ok or type(decoded) ~= "table" then return nil, "invalid JSON" end
  return decoded
end

local function repoApi(path)
  return "https://api.github.com/repos/" .. CFG.owner .. "/" .. CFG.repo .. "/" .. path
end

local function rawUrl(sha, path)
  return "https://raw.githubusercontent.com/" .. CFG.owner .. "/" .. CFG.repo .. "/" .. sha .. "/" .. path
end

local function currentCommit()
  local obj, err = requestJson(repoApi("commits/" .. textutils.urlEncode(CFG.ref)))
  if not obj then return nil, err end
  return obj.sha
end

local function getTree(sha)
  local obj, err = requestJson(repoApi("git/trees/" .. sha .. "?recursive=1"))
  if not obj then return nil, err end
  if obj.truncated then return nil, "GitHub tree response was truncated" end
  return obj.tree or {}
end

local function removeTree(path)
  if fs.exists(path) then fs.delete(path) end
end

local function stageCommit(sha)
  local state = loadState()
  local inactive = state.activeSlot == "A" and "B" or "A"
  local slot = join(CFG.root, inactive)
  removeTree(slot)
  ensureDir(slot)

  local tree, err = getTree(sha)
  if not tree then return nil, err end

  local wanted={}
  for _,item in ipairs(tree) do
    if item.type=="blob" and type(item.path)=="string" and item.path:sub(1,4)=="src/" then
      wanted[#wanted+1]=item
    end
  end
  runtime.total=#wanted
  runtime.progress=0
  setRuntime("UPDATING")

  local files, bytes = 0, 0
  for _, item in ipairs(wanted) do
    local rel = item.path:sub(5)
    local body, ferr = request(rawUrl(sha, item.path))
    if not body then
      removeTree(slot)
      return nil, "download " .. item.path .. ": " .. tostring(ferr)
    end
    local ok, werr = writeAll(join(slot, rel), body)
    if not ok then
      removeTree(slot)
      return nil, "write " .. rel .. ": " .. tostring(werr)
    end
    files = files + 1
    bytes = bytes + #body
    runtime.progress=files
    if files%5==0 or files==#wanted then draw() end
    sleep(0)
  end

  writeAll(join(slot, ".commit"), sha .. "\n")
  state.activeSlot = inactive
  state.commit = sha
  state.ref = CFG.ref
  state.files = files
  state.bytes = bytes
  state.updatedAt = os.epoch and os.epoch("utc") or 0
  local ok, serr = saveState(state)
  if not ok then return nil, serr end
  return state
end

function M.activeRoot()
  local state = loadState()
  return join(CFG.root, state.activeSlot)
end

function M.status()
  local state = loadState()
  state.root = M.activeRoot()
  state.repo = CFG.owner .. "/" .. CFG.repo
  state.protocol = CFG.protocol
  state.managerState = runtime.state
  state.lastError = runtime.lastError
  return state
end

function M.sync(force)
  runtime.lastCheck=os.date and os.date("%H:%M:%S") or tostring(os.epoch("utc"))
  runtime.changed=false
  setRuntime("CHECKING")

  local sha, err = currentCommit()
  if not sha then
    setRuntime("DEGRADED",err)
    return nil, err
  end

  local state = loadState()
  if not force and state.commit == sha and fs.exists(M.activeRoot()) then
    runtime.progress=0
    runtime.total=state.files or 0
    setRuntime("HEALTHY")
    return state, false
  end

  local nextState, serr = stageCommit(sha)
  if not nextState then
    setRuntime("DEGRADED",serr)
    return nil, serr
  end

  runtime.changed=true
  runtime.progress=nextState.files or 0
  runtime.total=nextState.files or 0
  setRuntime("HEALTHY")
  return nextState, true
end

local function rememberNode(sender,msg)
  local n=runtime.nodes[sender] or {}
  n.lastSeen=os.epoch and os.epoch("utc") or 0
  if type(msg)=="table" then
    n.hostname=msg.hostname or (msg.status and msg.status.hostname) or n.hostname
    n.role=msg.role or (msg.status and msg.status.role) or n.role
    n.status=msg.status or n.status
  end
  runtime.nodes[sender]=n
end

local function serveOne(sender, msg)
  if type(msg) ~= "table" or msg.protocol ~= CFG.protocol then return end
  rememberNode(sender,msg)

  if msg.op == "status" then
    rednet.send(sender, { protocol = CFG.protocol, op = "status", ok = true, status = M.status() }, CFG.protocol)
  elseif msg.op == "sync" then
    local state, changedOrErr = M.sync(msg.force == true)
    if state then
      rednet.send(sender, { protocol = CFG.protocol, op = "sync", ok = true, changed = changedOrErr == true, status = state }, CFG.protocol)
    else
      rednet.send(sender, { protocol = CFG.protocol, op = "sync", ok = false, error = changedOrErr }, CFG.protocol)
    end
  elseif msg.op == "read" and type(msg.path) == "string" then
    local rel = fs.combine("", msg.path)
    if rel:sub(1, 2) == ".." then
      rednet.send(sender, { protocol = CFG.protocol, op = "read", ok = false, error = "invalid path" }, CFG.protocol)
      return
    end
    local path = join(M.activeRoot(), rel)
    local data = readAll(path)
    rednet.send(sender, { protocol = CFG.protocol, op = "read", ok = data ~= nil, path = rel, data = data }, CFG.protocol)
  end
  draw()
end

function M.run()
  os.setComputerLabel("LINUX_NETWORK")
  chooseMonitor()

  modemName = findWirelessModem()
  if modemName and not rednet.isOpen(modemName) then rednet.open(modemName) end

  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1,1)
  print("CCLUA-LINUX Network Manager")
  print("Dashboard: "..tostring(monitorName or "none"))
  print("Status lamp: "..CFG.statusSide)

  local state, changedOrErr = M.sync(false)
  if state then
    print(("GitHub %s @ %s"):format(changedOrErr and "updated" or "current",tostring(state.commit):sub(1,8)))
  else
    print("GitHub warning: "..tostring(changedOrErr))
  end

  local poll = os.startTimer(CFG.pollSeconds)
  local ui = os.startTimer(0.5)

  while true do
    local event, a, b = os.pullEvent()
    if event == "timer" and a == poll then
      M.sync(false)
      poll = os.startTimer(CFG.pollSeconds)
    elseif event=="timer" and a==ui then
      draw()
      ui=os.startTimer(0.5)
    elseif event == "rednet_message" then
      serveOne(a, b)
    elseif event=="monitor_resize" or event=="peripheral" or event=="peripheral_detach" then
      chooseMonitor()
      modemName=findWirelessModem()
      if modemName and not rednet.isOpen(modemName) then pcall(rednet.open,modemName) end
      draw()
    elseif event=="terminate" then
      pcall(redstone.setOutput,CFG.statusSide,false)
      return
    end
  end
end

return M
