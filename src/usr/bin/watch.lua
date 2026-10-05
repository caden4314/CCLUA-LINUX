local Exec=dofile("/usr/lib/cclua/exec.lua")

local function parse(args)
  local interval=2
  local title=true
  local cmd={}
  local i=1
  while i<=#(args or {}) do
    local a=args[i]
    if (a=="-n" or a=="--interval") and args[i+1] then
      interval=math.max(0.1,tonumber(args[i+1]) or 2)
      i=i+2
    elseif a=="-t" or a=="--no-title" then
      title=false
      i=i+1
    else
      cmd[#cmd+1]=a
      i=i+1
    end
  end
  return interval,title,cmd
end

return {main=function(ctx,args)
  local interval,title,cmd=parse(args)
  if #cmd==0 then
    print("watch: missing command")
    return 1
  end
  if ctx.pty then ctx.pty:set_alternate_screen(true) end

  while true do
    term.clear()
    term.setCursorPos(1,1)
    if title then
      term.setTextColor(colors.cyan)
      print(("Every %.1fs: %s"):format(interval,table.concat(cmd," ")))
      term.setTextColor(colors.gray)
      print((os.date and os.date("%Y-%m-%d %H:%M:%S")) or "CCLUA")
      print("")
      term.setTextColor(colors.white)
    end

    local code=Exec.run(ctx,cmd,{process_group=ctx.process.process_group})
    local _,h=term.getSize()
    term.setCursorPos(1,h)
    term.setTextColor(code==0 and colors.gray or colors.red)
    write(("exit=%d  q quit"):format(code))
    term.setTextColor(colors.white)

    local timer=os.startTimer and os.startTimer(interval) or nil
    local redraw=false
    while not redraw do
      local ev,a=coroutine.yield("wait_event",{"timer","char","term_resize"})
      if ev=="char" and tostring(a or ""):lower()=="q" then
        if ctx.pty then ctx.pty:set_alternate_screen(false) end
        return 0
      elseif ev=="term_resize" then
        redraw=true
      elseif ev=="timer" and (not timer or a==timer) then
        redraw=true
      end
    end
  end
end}
