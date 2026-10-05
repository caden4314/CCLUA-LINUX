local ui=dofile("/usr/lib/cclua/cli_ui.lua")

return {main=function(ctx,args)
  local batch=false
  for _,a in ipairs(args or {}) do if a=="-b" or a=="--batch" then batch=true end end

  if not batch then term.clear();term.setCursorPos(1,1) end
  local processes=ctx.kernel.process.all()
  local running,sleeping,failed=0,0,0
  for _,p in ipairs(processes) do
    local state=tostring(p.state or "unknown")
    if state=="running" then running=running+1
    elseif state=="crashed" or state=="killed" then failed=failed+1
    else sleeping=sleeping+1 end
  end

  local activeServices,failedServices=0,0
  for _,service in ipairs(ctx.kernel.services:list()) do
    if not service.reference or service.exec then
      if service.state=="active" then activeServices=activeServices+1 end
      if service.state=="failed" then failedServices=failedServices+1 end
    end
  end

  local w=select(1,term.getSize())
  term.setTextColor(colors.cyan)
  print(("top - %s  up %ds  CCLUA"):format(
    os.date and os.date("%H:%M:%S") or "--:--:--",math.floor(os.clock())
  ))
  term.setTextColor(colors.white)
  print(("Tasks: %d total, %d running, %d waiting, %d failed"):format(
    #processes,running,sleeping,failed
  ))
  term.setTextColor(failedServices>0 and colors.red or colors.lime)
  print(("Services: %d active, %d failed"):format(activeServices,failedServices))
  term.setTextColor(colors.white)

  ui.table_header(" PID USER       STATE       COMMAND")
  local commandWidth=math.max(8,w-31)
  for _,p in ipairs(processes) do
    local user=ctx.kernel.users.by_uid(p.uid)
    local name=(user and user.name) or tostring(p.uid)
    local state=tostring(p.state or "?")
    local command=tostring(p.name or (p.argv and p.argv[1]) or "?")
    write(("%4d %-10s "):format(tonumber(p.pid) or 0,name:sub(1,10)))
    term.setTextColor(ui.state_color(state))
    write(("%-11s"):format(state:sub(1,11)))
    term.setTextColor(colors.white)
    print(" "..command:sub(1,commandWidth))
  end
  ui.reset()
  return 0
end}
