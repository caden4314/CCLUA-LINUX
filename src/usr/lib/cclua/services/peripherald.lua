return function(ctx)
  local kernel=ctx.kernel
  local config=dofile("/usr/lib/cclua/config.lua")
  local drivers=dofile("/usr/lib/cclua/drivers.lua")

  local function device_count()
    local n=0
    for _ in pairs(kernel.device.devices) do n=n+1 end
    return n
  end

  local function refresh(reason,count,lastName)
    kernel.device.scan(kernel)
    kernel.device.snapshot()
    local devices=drivers.scan()
    local caps,providers=drivers.capabilities()
    config.write_json("/var/lib/cclua/drivers.json",{
      schema=1,timestamp=os.epoch and os.epoch("utc") or 0,
      devices=devices,native=drivers.native(),
      capabilities=caps,providers=providers,
    })
    if os.queueEvent then
      os.queueEvent("cclua_driver_changed",reason or "refresh",lastName)
    end
    kernel.log.write("info","peripherald","peripheral inventory refreshed",{
      reason=reason or "event-batch",
      batched_events=count or 0,
      last_peripheral=lastName,
      count=device_count()
    },ctx.process.pid)
  end

  refresh("startup",0,nil)
  kernel.log.write("info","peripherald","initial driver inventory complete",{
    count=device_count()
  },ctx.process.pid)

  local refreshTimer=nil
  local pendingCount=0
  local lastPeripheral=nil

  while true do
    local ev,name=coroutine.yield("wait_event",{"peripheral","peripheral_detach","timer","terminate"})

    if ev=="peripheral" or ev=="peripheral_detach" then
      pendingCount=pendingCount+1
      lastPeripheral=name

      if refreshTimer and os.cancelTimer then
        pcall(os.cancelTimer,refreshTimer)
      end
      refreshTimer=os.startTimer(0.40)

    elseif ev=="timer" and refreshTimer and name==refreshTimer then
      local count=pendingCount
      local last=lastPeripheral
      refreshTimer=nil
      pendingCount=0
      lastPeripheral=nil
      refresh("debounced-peripheral-events",count,last)

    elseif ev=="terminate" then
      return 0
    end
  end
end
