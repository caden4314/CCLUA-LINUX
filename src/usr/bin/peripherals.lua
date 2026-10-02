return {main=function(ctx,args)
  local verbose=false
  local json=false
  local refresh=false

  for _,a in ipairs(args) do
    if a=="-v" or a=="--verbose" then verbose=true
    elseif a=="--json" then json=true
    elseif a=="-r" or a=="--refresh" then refresh=true end
  end

  if refresh then
    ctx.kernel.device.scan(ctx.kernel)
    ctx.kernel.device.snapshot()
  end

  local devices={}
  for _,dev in pairs(ctx.kernel.device.devices) do devices[#devices+1]=dev end
  table.sort(devices,function(a,b)return a.name<b.name end)

  if json then
    local payload={schema=1,computer_id=os.getComputerID(),devices=devices}
    print(textutils.serializeJSON(payload))
    return 0
  end

  print(("Detected peripherals: %d"):format(#devices))
  if #devices==0 then
    print("(none)")
    return 0
  end

  for _,dev in ipairs(devices) do
    print(("%-18s %s"):format(dev.name,table.concat(dev.types or {},",")))
    if verbose and dev.methods and #dev.methods>0 then
      print("  methods: "..table.concat(dev.methods,", "))
    end
  end

  print("")
  print("Snapshot: /var/lib/cclua/peripherals.json")
  return 0
end}
