local M={}

local function set(c)
  if term and term.setTextColor then term.setTextColor(c) end
end

function M.reset()
  set(colors.white)
end

function M.state_color(state)
  state=tostring(state or ""):upper()
  if state=="HEALTHY" or state=="ONLINE" or state=="CURRENT"
    or state=="PASSED" or state=="ACTIVE" or state=="RUNNING"
    or state=="READY" or state=="ON" then return colors.lime end
  if state=="FAILED" or state=="DEGRADED" or state=="OFFLINE"
    or state=="NO_MODEM" or state=="ERROR" or state=="FAULT"
    or state=="CRASHED" then return colors.red end
  if state=="BOOTING" or state=="UPDATING" or state=="CHECKING"
    or state=="STAGING" or state=="VERIFYING" or state=="ACTIVATING"
    or state=="DOWNLOADING" then return colors.yellow end
  return colors.lightGray
end
function M.heading(text)
  set(colors.cyan)
  print(tostring(text or ""))
  set(colors.white)
end

function M.rule(width)
  width=math.max(3,tonumber(width) or 30)
  set(colors.gray)
  print(string.rep("-",width))
  set(colors.white)
end

function M.label(label,value,valueColor)
  set(colors.gray)
  write(("%-13s"):format(tostring(label or "")..":"))
  set(valueColor or colors.white)
  print(tostring(value or "-"))
  set(colors.white)
end

function M.status(label,state,detail)
  set(colors.gray)
  write(("%-13s"):format(tostring(label or "")..":"))
  set(M.state_color(state))
  write(tostring(state or "UNKNOWN"))
  if detail and detail~="" then
    set(colors.lightGray)
    write("  "..tostring(detail))
  end
  print("")
  set(colors.white)
end
function M.error(message,hint)
  set(colors.red)
  print("Error: "..tostring(message or "unknown error"))
  if hint and hint~="" then
    set(colors.lightGray)
    print("Hint:  "..tostring(hint))
  end
  set(colors.white)
end

function M.warning(message)
  set(colors.yellow)
  print("Warning: "..tostring(message or ""))
  set(colors.white)
end

function M.success(message)
  set(colors.lime)
  print(tostring(message or "OK"))
  set(colors.white)
end

function M.table_header(text)
  set(colors.lightBlue)
  print(tostring(text or ""))
  set(colors.white)
end

function M.dim(text)
  set(colors.gray)
  print(tostring(text or ""))
  set(colors.white)
end

return M
