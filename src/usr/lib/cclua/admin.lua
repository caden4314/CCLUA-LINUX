local config=dofile("/usr/lib/cclua/config.lua")
local net=dofile("/usr/lib/cclua/net.lua")
local M={}
local protocol="cclua-admin-v1"

local function manager_id()
  local machine=config.machine()
  return tonumber(machine.manager_computer_id) or 0
end

local function rpc(msg,timeout)
  msg=msg or {}
  msg.protocol=protocol
  msg.hostname=config.machine().hostname
  msg.role=config.machine().role

  net.open_management_modems()
  local target=manager_id()
  local ok=rednet.send(target,msg,protocol)
  if not ok then return nil,"unable to reach manager" end

  local timer=os.startTimer(tonumber(timeout) or 3)
  while true do
    local ev,a,b,c=coroutine.yield("wait_event",{"rednet_message","timer"})
    if ev=="timer" and a==timer then
      return nil,"manager request timed out"
    elseif ev=="rednet_message" and a==target and c==protocol and type(b)=="table" then
      if os.cancelTimer then pcall(os.cancelTimer,timer) end
      if b.ok~=true then return nil,b.error or "admin request failed" end
      return b.data
    end
  end
end

function M.snapshot()
  return rpc({op="snapshot"},3)
end

function M.lighting(command)
  return rpc({op="lighting",command=command},4)
end

function M.gps(command)
  return rpc({op="gps",command=command or {op="status"}},4)
end

function M.node(target,action,opts)
  opts=opts or {}
  return rpc({
    op="node",
    target=tonumber(target),
    action=action or "status",
    service=opts.service,
    service_action=opts.service_action
  },4)
end

return M
