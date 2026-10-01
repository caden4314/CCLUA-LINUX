local sha = ISO.require("system/lib/crypto/sha.lua")
local M = {}
local counter = 0

local function entropy()
  local parts = {
    tostring(os.getComputerID and os.getComputerID() or 0),
    tostring(os.clock()),
    tostring(os.epoch and os.epoch("utc") or os.time()),
    tostring(math.random()),
  }
  if peripheral and peripheral.getNames then
    local names = peripheral.getNames()
    table.sort(names)
    parts[#parts+1] = table.concat(names, ",")
  end
  return table.concat(parts, "|")
end

local seed = select(2, sha.sha256(entropy()))

function M.absorb(value)
  seed = select(2, sha.sha256(seed .. tostring(value) .. entropy()))
end

function M.bytes(count)
  local out = {}
  while #table.concat(out) < count do
    counter = counter + 1
    seed = select(2, sha.sha256(seed .. entropy() .. tostring(counter)))
    out[#out+1] = seed
  end
  return table.concat(out):sub(1,count)
end

return M
