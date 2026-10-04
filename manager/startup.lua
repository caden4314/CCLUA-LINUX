-- LINUX_NETWORK bootstrap for CCLUA-LINUX
-- Refreshes the manager bridge from GitHub, then runs the last known-good copy.

os.setComputerLabel("LINUX_NETWORK")
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("CCLUA-LINUX / LINUX_NETWORK")
print("Bootstrap ID " .. os.getComputerID())

local URL = "https://raw.githubusercontent.com/caden4314/CCLUA-LINUX/main/manager/github_bridge.lua"
local LIVE = "/github_bridge.lua"
local NEW = "/github_bridge.lua.new"
local OLD = "/github_bridge.lua.old"

local function download()
  local h, err = http.get(URL, {
    ["User-Agent"] = "CCLUA-LINUX/" .. tostring(os.getComputerID())
  })
  if not h then return nil, err or "HTTP request failed" end
  local code = h.getResponseCode and h.getResponseCode() or 200
  local body = h.readAll()
  h.close()
  if code < 200 or code >= 300 then return nil, "HTTP " .. tostring(code) end

  local out, werr = fs.open(NEW, "w")
  if not out then return nil, werr or "cannot open staging file" end
  out.write(body)
  out.close()

  local fn, lerr = load(body, "@github_bridge.lua", "t", _ENV)
  if not fn then
    fs.delete(NEW)
    return nil, "downloaded bridge failed syntax check: " .. tostring(lerr)
  end

  if fs.exists(OLD) then fs.delete(OLD) end
  if fs.exists(LIVE) then fs.move(LIVE, OLD) end
  fs.move(NEW, LIVE)
  return true
end

local ok, err = download()
if ok then
  print("Manager bootstrap refreshed.")
else
  print("GitHub bootstrap warning: " .. tostring(err))
end

if not fs.exists(LIVE) and fs.exists(OLD) then fs.move(OLD, LIVE) end
if not fs.exists(LIVE) then
  error("No GitHub manager bridge is available.", 0)
end

local loaded, bridge = pcall(dofile, LIVE)
if not loaded or type(bridge) ~= "table" or type(bridge.run) ~= "function" then
  print("Manager bridge failed to load: " .. tostring(bridge))
  if fs.exists(OLD) then
    local oldOk, oldBridge = pcall(dofile, OLD)
    if oldOk and type(oldBridge) == "table" and type(oldBridge.run) == "function" then
      print("Falling back to previous manager bridge.")
      return oldBridge.run()
    end
  end
  error("No valid manager bridge could be started.", 0)
end

bridge.run()
