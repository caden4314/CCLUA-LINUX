return function(ctx)
  local kernel=ctx.kernel

  kernel.device.scan(kernel)
  kernel.device.snapshot()
  kernel.log.write("info","peripherald","initial peripheral inventory complete",{
    count=(function() local n=0 for _ in pairs(kernel.device.devices) do n=n+1 end return n end)()
  },ctx.process.pid)

  while true do
    local ev,name=coroutine.yield("wait_event")
    if ev=="peripheral" or ev=="peripheral_detach" then
      kernel.device.scan(kernel)
      kernel.device.snapshot()
      kernel.log.write("info","peripherald","peripheral inventory refreshed",{
        event=ev,
        peripheral=name
      },ctx.process.pid)
    end
  end
end
