-- CCLUA-LINUX manager GitHub bridge
-- Runs on the cluster's LINUX_NETWORK computer.
-- Public-repository pull path: no GitHub credential is stored in-world.

local M = {}

local CFG = {
  owner = "caden4314",
  repo = "CCLUA-LINUX",
  ref = "main",
  root = "/var/lib/cclua/github",
  protocol = "cclua-manager-v1",
  pollSeconds = 120,
}

local function join(a, b)
  if a:sub(-1) == "/" then return a .. b end
  return a .. "/" .. b
end

local function ensureDir(path)
  if fs.exists(path) then return end
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

  local files, bytes = 0, 0
  for _, item in ipairs(tree) do
    if item.type == "blob" and type(item.path) == "string" and item.path:sub(1, 4) == "src/" then
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
      if files % 10 == 0 then
        print(("  synced %d files (%d KiB)"):format(files, math.floor(bytes / 1024)))
        sleep(0)
      end
    end
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
  return state
end

function M.sync(force)
  ensureDir(CFG.root)
  local sha, err = currentCommit()
  if not sha then return nil, err end
  local state = loadState()
  if not force and state.commit == sha and fs.exists(M.activeRoot()) then
    return state, false
  end
  print("GitHub update: " .. tostring(state.commit or "none"):sub(1, 8) .. " -> " .. sha:sub(1, 8))
  local nextState, serr = stageCommit(sha)
  if not nextState then return nil, serr end
  return nextState, true
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

local function serveOne(sender, msg)
  if type(msg) ~= "table" or msg.protocol ~= CFG.protocol then return end
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
end

function M.run()
  os.setComputerLabel("LINUX_NETWORK")
  local modem = findWirelessModem()
  if modem and not rednet.isOpen(modem) then rednet.open(modem) end

  print("CCLUA-LINUX GitHub bridge")
  print("Repo: " .. CFG.owner .. "/" .. CFG.repo .. " [" .. CFG.ref .. "]")
  if modem then print("Network: " .. modem .. " / " .. CFG.protocol) else print("Network: no wireless modem") end

  local state, changedOrErr = M.sync(false)
  if state then
    print((changedOrErr and "Updated " or "Current ") .. tostring(state.commit):sub(1, 8) .. " (" .. tostring(state.files or "?") .. " files)")
  else
    print("Initial sync failed: " .. tostring(changedOrErr))
  end

  local timer = os.startTimer(CFG.pollSeconds)
  while true do
    local event, a, b, c = os.pullEvent()
    if event == "timer" and a == timer then
      local okState, changed = M.sync(false)
      if okState and changed then print("Repository updated to " .. tostring(okState.commit):sub(1, 8)) end
      if not okState then print("Sync warning: " .. tostring(changed)) end
      timer = os.startTimer(CFG.pollSeconds)
    elseif event == "rednet_message" then
      serveOne(a, b)
    end
  end
end

return M
