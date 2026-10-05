local ui=dofile("/usr/lib/cclua/cli_ui.lua")

local function count_services(ctx)
  local active,failed=0,0
  for _,service in ipairs(ctx.kernel.services:list()) do
    if not service.reference or service.exec then
      if service.state=="active" then active=active+1 end
      if service.state=="failed" then failed=failed+1 end
    end
  end
  return active,failed
end

local function process_rows(ctx,sortMode)
  local rows={}
  for _,p in ipairs(ctx.kernel.process.all()) do rows[#rows+1]=p end
  table.sort(rows,function(a,b)
    if sortMode=="cpu" then
      if (a.cpu_resumes or 0)~=(b.cpu_resumes or 0) then
        return (a.cpu_resumes or 0)>(b.cpu_resumes or 0)
      end
    elseif sortMode=="state" and tostring(a.state)~=tostring(b.state) then
      return tostring(a.state)<tostring(b.state)
    end
    return (a.pid or 0)<(b.pid or 0)
  end)
  return rows
end

local function draw(ctx,sortMode)
  term.clear()
  term.setCursorPos(1,1)
  local processes=process_rows(ctx,sortMode)
  local running,waiting,failed=0,0,0
  for _,p in ipairs(processes) do
    local state=tostring(p.state or "unknown")
    if state=="running" or state=="runnable" then running=running+1
    elseif state=="crashed" or state=="killed" then failed=failed+1
    else waiting=waiting+1 end
  end

  local activeServices,failedServices=count_services(ctx)
  local w,h=term.getSize()
  term.setTextColor(colors.cyan)
  print(("top - %s  up %ds  CCLUA  sort=%s"):format(
    os.date and os.date("%H:%M:%S") or "--:--:--",
    math.floor(os.clock()),sortMode
  ))
  term.setTextColor(colors.white)
  print(("Tasks: %d total, %d running, %d waiting, %d failed"):format(
    #processes,running,waiting,failed
  ))
  term.setTextColor(failedServices>0 and colors.red or colors.lime)
  print(("Services: %d active, %d failed"):format(activeServices,failedServices))
  term.setTextColor(colors.white)

  ui.table_header(" PID USER       STATE       RESUMES COMMAND")
  local commandWidth=math.max(8,w-40)
  local limit=math.max(0,h-5)
  for i=1,math.min(limit,#processes) do
    local p=processes[i]
    local user=ctx.kernel.users.by_uid(p.uid)
    local name=(user and user.name) or tostring(p.uid)
    local state=tostring(p.state or "?")
    local command=tostring(p.name or (p.argv and p.argv[1]) or "?")
    write(("%4d %-10s "):format(tonumber(p.pid) or 0,name:sub(1,10)))
    term.setTextColor(ui.state_color(state))
    write(("%-11s"):format(state:sub(1,11)))
    term.setTextColor(colors.white)
    print((" %7d %s"):format(p.cpu_resumes or 0,command:sub(1,commandWidth)))
  end

  term.setCursorPos(1,h)
  term.setTextColor(colors.gray)
  write("q quit  p pid  c activity  s state")
  ui.reset()
end
return {main=function(ctx,args)
  local batch=false
  local delay=1
  for i,a in ipairs(args or {}) do
    if a=="-b" or a=="--batch" then batch=true
    elseif (a=="-d" or a=="--delay") and args[i+1] then
      delay=math.max(0.1,tonumber(args[i+1]) or 1)
    end
  end

  if batch then draw(ctx,"pid");return 0 end

  if ctx.pty then ctx.pty:set_alternate_screen(true) end
  local sortMode="activity"
  while true do
    draw(ctx,sortMode=="activity" and "cpu" or sortMode)
    local timer=os.startTimer and os.startTimer(delay) or nil
    while true do
      local ev,a=coroutine.yield("wait_event",{"timer","char","key","term_resize"})
      if ev=="char" then
        local ch=tostring(a or ""):lower()
        if ch=="q" then
          if ctx.pty then ctx.pty:set_alternate_screen(false) end
          return 0
        elseif ch=="p" then sortMode="pid";break
        elseif ch=="c" then sortMode="activity";break
        elseif ch=="s" then sortMode="state";break
        end
      elseif ev=="timer" and (not timer or a==timer) then
        break
      elseif ev=="term_resize" then
        break
      end
    end
  end
end}
