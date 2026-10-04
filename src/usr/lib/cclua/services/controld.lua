return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local net=dofile("/usr/lib/cclua/net.lua")
  local machine=config.machine()
  local protocol="cclua-control-v1"
  local managerId=tonumber(machine.manager_computer_id) or 0
  local rebootTimer=nil
  local shutdownTimer=nil

  local function service_rows()
    local out={}
    for _,u in ipairs(ctx.kernel.services:list()) do
      if not u.reference then
        out[#out+1]={
          name=u.name,
          state=u.state,
          pid=u.pid,
          enabled=u.enabled==true,
          error=u.error
        }
      end
    end
    return out
  end

  local function status()
    local update=config.read_json("/var/lib/cclua/update-state.json",{})
    local sys=config.read_json("/var/lib/cclua/status.json",{})
    return {
      schema=1,
      hostname=machine.hostname,
      computer_id=os.getComputerID(),
      role=machine.role,
      system_state=sys.state or sys.system_state or "UNKNOWN",
      update=update,
      processes=#ctx.kernel.process.all(),
      services=service_rows(),
      timestamp=os.epoch and os.epoch("utc") or 0
    }
  end

  local function reply(id,msg)
    rednet.send(id,msg,protocol)
  end

  local function reject(sender,op)
    ctx.kernel.log.write("warning","controld","rejected control request",{
      sender=sender,op=op
    },ctx.process.pid)
  end

  local function service_action(msg)
    local name=tostring(msg.service or "")
    if name=="" then return nil,"service name required" end
    local action=tostring(msg.action or "")
    if action=="start" then return ctx.kernel.services:start(name) end
    if action=="stop" then return ctx.kernel.services:stop(name) end
    if action=="restart" then return ctx.kernel.services:restart(name) end
    return nil,"unsupported service action"
  end

  net.open_management_modems()
  ctx.unit.details={protocol=protocol,manager_id=managerId}
  ctx.kernel.log.write("info","controld","node control service online",ctx.unit.details,ctx.process.pid)

  while true do
    local ev,a,b,c=coroutine.yield("wait_event",{
      "rednet_message","timer","peripheral","peripheral_detach","terminate"
    })

    if ev=="rednet_message" and c==protocol and type(b)=="table" then
      if a~=managerId then
        reject(a,b.op)
      elseif b.protocol~=protocol then
        reject(a,b.op)
      elseif b.op=="status" then
        reply(a,{protocol=protocol,op="status",ok=true,state=status()})
      elseif b.op=="service" then
        local ok,res=service_action(b)
        ctx.kernel.log.write(ok and "info" or "warning","controld","remote service action",{
          sender=a,service=b.service,action=b.action,error=ok and nil or res
        },ctx.process.pid)
        reply(a,{protocol=protocol,op="service",ok=ok==true,error=ok and nil or res,state=status()})
      elseif b.op=="reboot" then
        reply(a,{protocol=protocol,op="reboot",ok=true,state=status()})
        ctx.kernel.log.write("warning","controld","remote reboot requested",{sender=a},ctx.process.pid)
        rebootTimer=os.startTimer(0.35)
      elseif b.op=="shutdown" then
        reply(a,{protocol=protocol,op="shutdown",ok=true,state=status()})
        ctx.kernel.log.write("warning","controld","remote shutdown requested",{sender=a},ctx.process.pid)
        shutdownTimer=os.startTimer(0.35)
      else
        reply(a,{protocol=protocol,op=b.op,ok=false,error="unknown operation"})
      end

    elseif ev=="timer" and rebootTimer and a==rebootTimer then
      rebootTimer=nil
      os.reboot()
    elseif ev=="timer" and shutdownTimer and a==shutdownTimer then
      shutdownTimer=nil
      os.shutdown()
    elseif ev=="peripheral" or ev=="peripheral_detach" then
      net.open_management_modems()
    elseif ev=="terminate" then
      return 0
    end
  end
end
