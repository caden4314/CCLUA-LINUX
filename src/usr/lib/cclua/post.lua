local config=dofile("/usr/lib/cclua/config.lua")
local monitorLayout=dofile("/usr/lib/cclua/monitor_layout.lua")
local native=dofile("/usr/lib/cclua/native.lua")
local M={}

local function now()
  return os.epoch and os.epoch("utc") or 0
end

local function host(path)
  return tostring(path or ""):gsub("^/","")
end

local function count_table(t)
  local n=0
  for _ in pairs(t or {}) do n=n+1 end
  return n
end

local function append_jsonl(path,value)
  local hp=host(path)
  local dir=fs.getDir(hp)
  if dir~="" and not fs.exists(dir) then pcall(fs.makeDir,dir) end
  local h=fs.open(hp,"a")
  if not h then return false end
  local ok,json=pcall(textutils.serializeJSON,value)
  if ok and json then h.writeLine(json) end
  h.close()
  return ok
end

local function status_color(state)
  if state=="PASS" then return colors.lime end
  if state=="WARN" then return colors.yellow end
  if state=="FAIL" then return colors.red end
  return colors.lightGray
end

local function status_mark(state)
  if state=="PASS" then return " OK " end
  if state=="WARN" then return "WARN" end
  if state=="FAIL" then return "FAIL" end
  return "...."
end

local function monitor_targets(machine)
  local out={}
  local seen={}
  local preferred=machine.post_monitor or machine.monitor_side

  local function add(name,obj)
    if not name or not obj or seen[name] then return end
    seen[name]=true
    out[#out+1]={name=name,obj=obj}
  end

  if preferred and peripheral.getType(preferred)=="monitor" then
    add(preferred,peripheral.wrap(preferred))
  end

  if machine.post_mirror_all_monitors==true then
    for _,name in ipairs(peripheral.getNames()) do
      if peripheral.hasType(name,"monitor") then add(name,peripheral.wrap(name)) end
    end
  elseif #out==0 then
    local name=nil
    local obj=peripheral.find("monitor",function(n)
      if not name then name=n return true end
      return false
    end)
    if obj then add(name,obj) end
  end

  return out
end

local function setup_monitors(machine)
  local targets=monitor_targets(machine)
  for _,target in ipairs(targets) do
    local m=target.obj
    local fixed=nil
    if tostring(machine.monitor_ui_scale_mode or "auto"):lower()=="fixed" then
      fixed=tonumber(machine.post_monitor_text_scale or machine.monitor_text_scale)
    end
    monitorLayout.fit(m,{
      min_width=46,min_height=16,max_scale=3.0,fixed_scale=fixed,
    })
    pcall(m.setCursorBlink,false)
    pcall(m.setBackgroundColor,colors.black)
    pcall(m.setTextColor,colors.white)
    pcall(m.clear)
  end
  return targets
end

local function fit(s,n)
  s=tostring(s or "")
  if n<=0 then return "" end
  if #s<=n then return s end
  if n<=3 then return s:sub(1,n) end
  return s:sub(1,n-3).."..."
end

local function render_monitor(target,machine,records,phase,summary)
  local m=target.obj
  local ok=pcall(function()
    local w,h=m.getSize()
    m.setBackgroundColor(colors.black)
    m.setTextColor(colors.white)
    m.clear()

    m.setBackgroundColor(colors.blue)
    m.setCursorPos(1,1)
    m.write(string.rep(" ",w))
    m.setCursorPos(2,1)
    m.setTextColor(colors.white)
    m.write(fit("CCLUA POWER-ON SELF TEST",w-2))

    if h>=2 then
      m.setBackgroundColor(colors.gray)
      m.setCursorPos(1,2)
      m.write(string.rep(" ",w))
      m.setCursorPos(2,2)
      m.setTextColor(colors.white)
      m.write(fit((machine.hostname or "cclua").." | "..(machine.role or "unknown").." | ID "..os.getComputerID(),w-2))
    end

    m.setBackgroundColor(colors.black)
    local start=4
    local available=math.max(0,h-start)
    local first=math.max(1,#records-available+1)
    local y=start
    for i=first,#records do
      if y>h-1 then break end
      local rec=records[i]
      local col=status_color(rec.state)
      m.setCursorPos(2,y)
      m.setTextColor(col)
      m.write("["..status_mark(rec.state).."]")
      m.setTextColor(colors.white)
      m.setCursorPos(9,y)
      m.write(fit(rec.label or rec.id,w-10))
      if rec.detail and w>=55 then
        local detail=fit(rec.detail,math.floor(w*0.42))
        m.setTextColor(colors.gray)
        m.setCursorPos(math.max(10,w-#detail),y)
        m.write(detail)
      end
      y=y+1
    end

    if h>=3 then
      m.setCursorPos(1,h)
      local state=summary and summary.state or phase or "RUNNING"
      local col=status_color(state=="PASSED" and "PASS" or state=="DEGRADED" and "WARN" or state=="FAILED" and "FAIL" or "RUN")
      m.setBackgroundColor(colors.gray)
      m.setTextColor(col)
      m.write(fit((" POST %-9s  pass %d warn %d fail %d "):format(
        tostring(state),
        summary and summary.pass or 0,
        summary and summary.warn or 0,
        summary and summary.fail or 0
      ),w))
      local x=m.getCursorPos()
      if x<=w then m.write(string.rep(" ",w-x+1)) end
    end
  end)
  return ok
end

local function render_all(monitors,machine,records,phase,summary)
  for _,target in ipairs(monitors) do
    render_monitor(target,machine,records,phase,summary)
  end
end

local function terminal_header(machine)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1,1)
  term.setTextColor(colors.cyan)
  print("CCLUA POWER-ON SELF TEST")
  term.setTextColor(colors.lightGray)
  print(("%s | %s | computer %d"):format(
    machine.hostname or "cclua",
    machine.role or "unknown",
    os.getComputerID()
  ))
  print(string.rep("-",math.min(select(1,term.getSize()),72)))
end

local function terminal_result(rec)
  term.setTextColor(status_color(rec.state))
  write("["..status_mark(rec.state).."] ")
  term.setTextColor(colors.white)
  write(tostring(rec.label or rec.id))
  if rec.detail and rec.detail~="" then
    term.setTextColor(colors.gray)
    write(" - "..tostring(rec.detail))
  end
  print()
end

local function safe_check(check,ctx,machine)
  local started=now()
  local ok,a,b=pcall(check.run,ctx,machine)
  local state,detail

  if not ok then
    state=check.critical and "FAIL" or "WARN"
    detail="check error: "..tostring(a)
  elseif a==true then
    state="PASS"
    detail=b
  elseif a=="WARN" then
    state="WARN"
    detail=b
  else
    state=check.critical and "FAIL" or "WARN"
    detail=b or tostring(a or "check failed")
  end

  return {
    id=check.id,
    label=check.label,
    critical=check.critical==true,
    state=state,
    detail=detail,
    started_at=started,
    finished_at=now(),
  }
end

local function checks_for(ctx,machine)
  local checks={}

  local function add(id,label,critical,fn)
    checks[#checks+1]={id=id,label=label,critical=critical,run=fn}
  end

  add("kernel","Kernel runtime",true,function()
    local k=ctx.kernel
    local ok=k and k.version and k.process and k.scheduler and k.services and k.vfs and k.device
    if not ok then return false,"kernel subsystem missing" end
    return true,(k.version.version or "?").." ABI "..tostring(k.version.kernel_abi or "?")
  end)

  add("native","Native runtime",false,function()
    local available=native.available()
    local version=native.version()
    local caps=native.capabilities()
    config.write_json("/var/lib/cclua/native.json",{
      schema=1,
      available=available,
      version=version,
      capabilities=caps,
      computer=native.computer(),
      checked_at=now(),
    })
    if not available then return true,"stock CC:Tweaked fallback" end

    if caps.native_crc32 and caps.native_sha256 and caps.native_deflate then
      local crc,crcErr=native.crc32("123456789")
      if crc~=3421780262 then return "WARN","native CRC32 self-test failed: "..tostring(crcErr or crc) end
      local sha,shaErr=native.sha256("abc")
      if sha~="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" then
        return "WARN","native SHA-256 self-test failed: "..tostring(shaErr or sha)
      end
      local packed,packErr=native.deflate("CCLUA native codec self-test",6)
      if not packed then return "WARN","native deflate failed: "..tostring(packErr) end
      local unpacked,unpackErr=native.inflate(packed,1024)
      if unpacked~="CCLUA native codec self-test" then
        return "WARN","native inflate failed: "..tostring(unpackErr or "round-trip mismatch")
      end
    end

    return true,("CCPerf %s API %s / %s timer"):format(
      tostring(version or "?"),tostring(caps.api or "?"),
      caps.native_timer and "native" or "stock")
  end)

  add("filesystem","Filesystem read/write",true,function()
    local dir="var/lib/cclua"
    if not fs.exists(dir) then fs.makeDir(dir) end
    local free=fs.getFreeSpace and fs.getFreeSpace("/") or nil
    if type(free)=="number" and free<65536 then
      return false,("disk space critically low: %d bytes free"):format(free)
    end
    local path=dir.."/.post-write-test"
    local token=("post-%d-%d"):format(os.getComputerID(),now())
    local h=fs.open(path,"w")
    if not h then
      return false,"cannot open /var/lib/cclua for write"..(free and ("; free "..tostring(free)) or "")
    end
    h.write(token);h.close()
    h=fs.open(path,"r")
    if not h then return false,"cannot reopen POST test file" end
    local got=h.readAll();h.close()
    pcall(fs.delete,path)
    if got~=token then return false,"filesystem readback mismatch" end
    local free=fs.getFreeSpace and fs.getFreeSpace("/") or "?"
    return true,"free "..tostring(free)
  end)

  add("config","Machine configuration",true,function()
    if type(machine)~="table" then return false,"machine.json unavailable" end
    if not machine.hostname or machine.hostname=="" then return false,"hostname missing" end
    if not machine.role or machine.role=="" then return false,"role missing" end
    return true,tostring(machine.hostname).." / "..tostring(machine.role)
  end)

  add("image","System image",true,function()
    local required={
      "System/kernel/init.lua",
      "System/kernel/scheduler.lua",
      "System/init/init.lua",
      "usr/lib/cclua/config.lua",
      "usr/lib/cclua/service_manager.lua",
      "usr/lib/cclua/services/netd.lua",
    }
    local missing={}
    for _,path in ipairs(required) do if not fs.exists(path) then missing[#missing+1]=path end end
    if #missing>0 then return false,"missing "..table.concat(missing,", ") end
    local h=fs.open("var/lib/cclua/installed-commit","r")
    local commit=h and h.readAll() or nil
    if h then h.close() end
    return true,commit and ("image "..fit(commit:gsub("%s+",""),12)) or "core files present"
  end)

  add("devices","Peripheral bus",false,function()
    local devices=ctx.kernel.device.scan(ctx.kernel) or {}
    return true,tostring(count_table(devices)).." device(s)"
  end)

  add("network","Network interface",false,function()
    local modems={}
    for _,name in ipairs(peripheral.getNames()) do
      if peripheral.hasType(name,"modem") then modems[#modems+1]=name end
    end
    if #modems==0 then return "WARN","no modem attached" end
    return true,table.concat(modems,",")
  end)

  add("manager","Manager configuration",false,function()
    if machine.role=="manager" or machine.role=="network-manager" then
      return true,"local manager"
    end
    local id=tonumber(machine.manager_computer_id)
    if not id then return "WARN","manager_computer_id missing" end
    return true,"ID "..tostring(id)
  end)

  add("update","Previous update state",false,function()
    local u=config.read_json("/var/lib/cclua/update-state.json",{})
    local state=tostring(u.state or u.phase or "UNKNOWN"):upper()
    if state=="FAILED" or state=="ROLLBACK" then return "WARN",state end
    return true,state
  end)

  add("previous-health","Previous health state",false,function()
    local s=config.read_json("/var/lib/cclua/status.json",{})
    local state=tostring(s.state or "UNKNOWN"):upper()
    if state=="DEGRADED" or state=="FAILED" then
      return "WARN",state..(s.error_reason and (": "..tostring(s.error_reason)) or "")
    end
    return true,state
  end)

  if machine.role=="desktop-client" or tostring(machine.image or ""):find("desktop",1,true) then
    add("desktop","Desktop session assets",true,function()
      local required={
        "usr/bin/cclua-desktop.lua",
        "usr/lib/cclua/desktop/compositor.lua",
        "usr/lib/cclua/desktop/apps/terminal.lua",
      }
      local missing={}
      for _,path in ipairs(required) do if not fs.exists(path) then missing[#missing+1]=path end end
      if #missing>0 then return false,"missing "..table.concat(missing,", ") end
      local user=ctx.kernel.users and ctx.kernel.users.by_name and ctx.kernel.users.by_name("caden")
      if not user then return false,"desktop user caden missing" end
      local w,h=term.getSize()
      return true,("%dx%d terminal"):format(w,h)
    end)
  end

  local roleService={
    ["lighting-controller"]="usr/lib/cclua/services/lightingd.lua",
    ["app-server"]="usr/lib/cclua/services/apphostd.lua",
    ["fleet-monitor"]="usr/lib/cclua/services/server-room-monitor.lua",
    ["gps-control"]="usr/lib/cclua/services/gps-control.lua",
    ["gps-monitor"]="usr/lib/cclua/services/gps-monitor.lua",
    ["gps-host"]="usr/lib/cclua/services/gps-host.lua",
    ["theater-controller"]="usr/lib/cclua/services/theaterd.lua",
    ["manager"]="usr/lib/cclua/services/managerd.lua",
    ["network-manager"]="usr/lib/cclua/services/managerd.lua",
  }
  if roleService[machine.role] then
    add("role","Role service image",true,function()
      local path=roleService[machine.role]
      if not fs.exists(path) then return false,"missing "..path end
      return true,path:match("([^/]+)$")
    end)
  end

  add("display","POST display",false,function()
    local targets=monitor_targets(machine)
    if #targets==0 then
      local desktopRole=machine.role=="desktop-client"
        or tostring(machine.image or ""):find("desktop",1,true)~=nil
      if desktopRole or machine.dashboard_enabled==false then
        return true,"computer terminal"
      end
      return "WARN","server console only; no monitor attached"
    end
    local names={}
    for _,t in ipairs(targets) do names[#names+1]=t.name end
    return true,table.concat(names,",")
  end)

  return checks
end

function M.run(ctx,opts)
  opts=opts or {}
  local machine=config.machine()
  local monitors=opts.monitors==false and {} or setup_monitors(machine)
  local records={}

  terminal_header(machine)
  render_all(monitors,machine,records,"RUNNING",nil)

  local started=now()
  local checks=checks_for(ctx,machine)
  for _,check in ipairs(checks) do
    term.setTextColor(colors.lightGray)
    write("[....] "..check.label)
    local x,y=term.getCursorPos()
    term.setCursorPos(1,y)
    term.clearLine()

    local rec=safe_check(check,ctx,machine)
    records[#records+1]=rec
    terminal_result(rec)
    render_all(monitors,machine,records,"RUNNING",nil)

    if opts.animate~=false and ctx.kernel.scheduler and ctx.kernel.scheduler.sleep then
      ctx.kernel.scheduler.sleep(0.04)
    end
  end

  local pass,warn,fail,fatal=0,0,0,0
  for _,rec in ipairs(records) do
    if rec.state=="PASS" then pass=pass+1
    elseif rec.state=="WARN" then warn=warn+1
    elseif rec.state=="FAIL" then
      fail=fail+1
      if rec.critical then fatal=fatal+1 end
    end
  end

  local state=fatal>0 and "FAILED" or (warn>0 or fail>0) and "DEGRADED" or "PASSED"
  local summary={
    schema=1,
    state=state,
    passed=state=="PASSED",
    degraded=state=="DEGRADED",
    fatal=fatal>0,
    pass=pass,
    warn=warn,
    fail=fail,
    fatal_count=fatal,
    computer_id=os.getComputerID(),
    hostname=machine.hostname,
    role=machine.role,
    started_at=started,
    finished_at=now(),
    checks=records,
  }

  config.write_json("/var/lib/cclua/post.json",summary)
  append_jsonl("/var/log/cclua/post.jsonl",summary)
  render_all(monitors,machine,records,state,summary)

  term.setTextColor(state=="PASSED" and colors.lime or state=="DEGRADED" and colors.yellow or colors.red)
  print(string.rep("-",math.min(select(1,term.getSize()),72)))
  print(("POST %s: %d pass, %d warn, %d fail"):format(state,pass,warn,fail))
  term.setTextColor(colors.white)

  if ctx.kernel.log then
    ctx.kernel.log.write(
      fatal>0 and "critical" or warn>0 and "warning" or "info",
      "post",
      "power-on self test "..state:lower(),
      summary,
      ctx.process and ctx.process.pid or 1
    )
  end

  return summary
end

return M
