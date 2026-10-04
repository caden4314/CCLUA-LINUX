local M={}

local function now()
  return os.epoch and os.epoch("utc") or 0
end

local function persist(msg,details,trace)
  pcall(function()
    if not fs.exists("var") then fs.makeDir("var") end
    if not fs.exists("var/log") then fs.makeDir("var/log") end
    if not fs.exists("var/log/cclua") then fs.makeDir("var/log/cclua") end
    local payload={
      schema=1,
      timestamp=now(),
      computer_id=os.getComputerID and os.getComputerID() or nil,
      message=tostring(msg),
      details=details,
      traceback=trace,
    }
    local h=fs.open("var/log/cclua/panic.json","w")
    if h then h.write(textutils.serializeJSON(payload));h.close() end
    h=fs.open("var/log/cclua/panics.jsonl","a")
    if h then h.writeLine(textutils.serializeJSON(payload));h.close() end
  end)
end

local function monitor_panic(name,msg)
  local m=peripheral.wrap(name)
  if not m then return end
  pcall(function()
    -- Keep panic text physically readable even when CCPerf gives monitors
    -- a denser backing terminal.
    m.setTextScale(1.0)
    m.setCursorBlink(false)
    m.setBackgroundColor(colors.black)
    m.setTextColor(colors.white)
    m.clear()
    local w,h=m.getSize()

    m.setBackgroundColor(colors.red)
    m.setCursorPos(1,1)
    m.write(string.rep(" ",w))
    m.setCursorPos(2,1)
    m.setTextColor(colors.white)
    m.write("CCLUA KERNEL PANIC")

    m.setBackgroundColor(colors.black)
    m.setTextColor(colors.red)
    m.setCursorPos(2,3)
    local text=tostring(msg or "unknown panic")
    local y=3
    while #text>0 and y<h-3 do
      m.setCursorPos(2,y)
      m.write(text:sub(1,math.max(1,w-3)))
      text=text:sub(math.max(1,w-3)+1)
      y=y+1
    end

    if h>=6 then
      m.setTextColor(colors.lightGray)
      m.setCursorPos(2,h-2)
      m.write("Crash report: /var/log/cclua/panic.json")
      m.setCursorPos(2,h-1)
      m.write("Recovery: cclua-doctor status")
    end
  end)
end

function M.raise(k,msg,details)
  local trace=tostring(msg)
  if debug and debug.traceback then
    local ok,value=pcall(debug.traceback,tostring(msg),2)
    if ok and value then trace=tostring(value) end
  end
  if #trace>8000 then trace=trace:sub(1,8000).."\n<truncated>" end

  k.log.write("emerg","panic",msg,{details=details,traceback=trace})
  persist(msg,details,trace)

  if peripheral then
    for _,name in ipairs(peripheral.getNames()) do
      if peripheral.hasType(name,"monitor") then monitor_panic(name,msg) end
    end
  end

  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.red)
  term.clear()
  term.setCursorPos(1,1)
  print("CCLUA KERNEL PANIC")
  term.setTextColor(colors.white)
  print(tostring(msg))
  print("")
  term.setTextColor(colors.lightGray)
  print("Crash report: /var/log/cclua/panic.json")
  print("Recovery: cclua-doctor status")
  term.setTextColor(colors.white)
  error("KERNEL PANIC: "..tostring(msg),0)
end

return M
