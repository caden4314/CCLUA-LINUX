local config=dofile("/usr/lib/cclua/config.lua")
local exec=dofile("/usr/lib/cclua/exec.lua")
local pkgdb=dofile("/usr/lib/cclua/package_db.lua")

local M={}

local function fill(x1,y1,x2,y2,bg)
  term.setBackgroundColor(bg)
  for y=y1,y2 do
    term.setCursorPos(x1,y)
    write(string.rep(" ",math.max(0,x2-x1+1)))
  end
end

local function text(x,y,value,fg,bg)
  if bg then term.setBackgroundColor(bg) end
  term.setTextColor(fg or colors.white)
  term.setCursorPos(x,y)
  write(tostring(value))
end

local function center(y,value,fg,bg,x1,x2)
  local w=select(1,term.getSize())
  x1=x1 or 1
  x2=x2 or w
  value=tostring(value)
  if #value>x2-x1+1 then value=value:sub(1,x2-x1+1) end
  local x=x1+math.floor(((x2-x1+1)-#value)/2)
  text(x,y,value,fg,bg)
end

local function wait_return()
  local w,h=term.getSize()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.gray)
  center(h,"Press any key to return",colors.gray,colors.black)
  while true do
    local ev=coroutine.yield("wait_event",{"key","mouse_click","terminate"})
    if ev=="terminate" then return false end
    return true
  end
end

local function run_terminal(ctx)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1,1)
  exec.run(ctx,{"bash"},{cwd="/home/caden"})
end

local function run_files(ctx)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1,1)
  exec.run(ctx,{"cclua-files"},{cwd="/home/caden"})
end

local function show_system(ctx)
  local machine=config.machine()
  local w,h=term.getSize()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()

  fill(1,1,w,1,colors.blue)
  center(1,"Settings / About",colors.white,colors.blue)
  text(2,3,"Ubuntu 22.04.5 LTS Desktop",colors.orange,colors.black)
  text(2,5,"Device name",colors.gray,colors.black)
  text(math.min(18,w),5,machine.hostname or "test-client",colors.white,colors.black)
  text(2,6,"Computer ID",colors.gray,colors.black)
  text(math.min(18,w),6,tostring(os.getComputerID()),colors.white,colors.black)
  text(2,7,"IPv4",colors.gray,colors.black)
  text(math.min(18,w),7,machine.address or "unconfigured",colors.white,colors.black)
  text(2,8,"Image",colors.gray,colors.black)
  text(math.min(18,w),8,machine.image or "ubuntu-22.04-desktop",colors.white,colors.black)
  text(2,9,"Kernel",colors.gray,colors.black)
  text(math.min(18,w),9,tostring(ctx.kernel.version.version),colors.white,colors.black)
  text(2,10,"Kernel ABI",colors.gray,colors.black)
  text(math.min(18,w),10,tostring(ctx.kernel.version.kernel_abi),colors.white,colors.black)
  text(2,11,"Processes",colors.gray,colors.black)
  text(math.min(18,w),11,tostring(#ctx.kernel.process.all()),colors.white,colors.black)

  local peripherals=0
  for _ in pairs(ctx.kernel.device.devices or {}) do peripherals=peripherals+1 end
  text(2,12,"Peripherals",colors.gray,colors.black)
  text(math.min(18,w),12,tostring(peripherals),colors.white,colors.black)
  wait_return()
end

local function show_packages()
  local meta=pkgdb.load()
  local w,h=term.getSize()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  fill(1,1,w,1,colors.blue)
  center(1,"Ubuntu Software",colors.white,colors.blue)
  text(2,3,"Ubuntu 22.04.5 Desktop package reference",colors.orange,colors.black)
  text(2,5,"Reference packages:",colors.gray,colors.black)
  text(22,5,tostring(meta.package_count or #(meta.packages or {})),colors.white,colors.black)
  text(2,7,"Package backend:",colors.gray,colors.black)
  text(19,7,"CCLUA-native",colors.lime,colors.black)
  text(2,9,"CLI:",colors.gray,colors.black)
  text(8,9,"apt search <name>",colors.white,colors.black)
  text(8,10,"apt show <name>",colors.white,colors.black)
  text(8,11,"dpkg -l",colors.white,colors.black)
  text(2,13,"Package mutation is still under construction.",colors.yellow,colors.black)
  wait_return()
end

function M.main(ctx,args)
  local machine=config.machine()
  local zones={}
  local running=true
  local timer=nil

  ctx.process.environment.HOME=ctx.process.environment.HOME or "/home/caden"
  ctx.process.environment.USER=ctx.process.environment.USER or "caden"
  ctx.process.environment.LOGNAME=ctx.process.environment.LOGNAME or "caden"
  ctx.process.environment.DESKTOP_SESSION="ubuntu"
  ctx.process.environment.XDG_SESSION_TYPE="cclua"
  ctx.process.environment.XDG_CURRENT_DESKTOP="ubuntu:GNOME"
  ctx.process.environment.XDG_SESSION_DESKTOP="ubuntu"

  local function draw()
    local w,h=term.getSize()
    zones={}
    term.setCursorBlink(false)
    term.setBackgroundColor(colors.purple)
    term.setTextColor(colors.white)
    term.clear()

    fill(1,1,w,1,colors.gray)
    text(2,1,"Activities",colors.white,colors.gray)
    center(1,"Ubuntu 22.04",colors.white,colors.gray)
    local clock=os.date and os.date("%H:%M") or ""
    text(math.max(1,w-#clock-1),1,clock,colors.white,colors.gray)

    center(4,"Ubuntu Desktop",colors.white,colors.purple)
    center(5,machine.label or "TEST_CLIENT",colors.lightGray,colors.purple)
    center(7,"Computer-only session",colors.lightGray,colors.purple)

    local names={"Terminal","Files","System","Packages"}
    local keysHint={"T","F","S","P"}
    local widths={}
    local total=0
    for i,name in ipairs(names) do
      widths[i]=math.max(9,#name+4)
      total=total+widths[i]
    end
    total=total+(#names-1)
    local start=math.max(1,math.floor((w-total)/2)+1)
    local y1=math.max(10,h-6)
    local y2=math.min(h-2,y1+3)
    local x=start
    for i,name in ipairs(names) do
      local x2=math.min(w,x+widths[i]-1)
      fill(x,y1,x2,y2,colors.lightGray)
      center(y1+1,name,colors.black,colors.lightGray,x,x2)
      center(y1+2,"["..keysHint[i].."]",colors.gray,colors.lightGray,x,x2)
      zones[#zones+1]={name=name:lower(),x1=x,x2=x2,y1=y1,y2=y2}
      x=x2+2
    end

    center(h,"CCLUA Desktop session | Q logout",colors.lightGray,colors.purple)
  end

  local function activate(name)
    if name=="terminal" then run_terminal(ctx)
    elseif name=="files" then run_files(ctx)
    elseif name=="system" then show_system(ctx)
    elseif name=="packages" then show_packages() end
    draw()
  end

  draw()
  timer=os.startTimer(1)

  while running do
    local ev,a,b,c=coroutine.yield("wait_event",{
      "timer","mouse_click","key","char","term_resize","terminate"
    })

    if ev=="timer" and a==timer then
      local w=select(1,term.getSize())
      local clock=os.date and os.date("%H:%M") or ""
      fill(math.max(1,w-8),1,w,1,colors.gray)
      text(math.max(1,w-#clock-1),1,clock,colors.white,colors.gray)
      timer=os.startTimer(1)

    elseif ev=="mouse_click" then
      local x,y=b,c
      for _,z in ipairs(zones) do
        if x>=z.x1 and x<=z.x2 and y>=z.y1 and y<=z.y2 then
          activate(z.name)
          break
        end
      end

    elseif ev=="char" then
      local ch=tostring(a):lower()
      if ch=="t" then activate("terminal")
      elseif ch=="f" then activate("files")
      elseif ch=="s" then activate("system")
      elseif ch=="p" then activate("packages")
      elseif ch=="q" then running=false end

    elseif ev=="key" and a==keys.q then
      running=false

    elseif ev=="term_resize" then
      draw()

    elseif ev=="terminate" then
      running=false
    end
  end

  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1,1)
  return 0
end

return M
