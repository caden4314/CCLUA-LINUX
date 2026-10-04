local Canvas=dofile("/usr/lib/cclua/desktop/canvas.lua")
local Terminal=dofile("/usr/lib/cclua/desktop/apps/terminal.lua")
local Files=dofile("/usr/lib/cclua/desktop/apps/files.lua")
local System=dofile("/usr/lib/cclua/desktop/apps/system.lua")
local Packages=dofile("/usr/lib/cclua/desktop/apps/packages.lua")

local M={}
local APP={
  terminal={title="Terminal",icon=">_",mod=Terminal},
  files={title="Files",icon="[]",mod=Files},
  system={title="Settings",icon="*",mod=System},
  packages={title="Software",icon="#",mod=Packages},
}
local ORDER={"terminal","files","system","packages"}

local function tune_palette()
  local p=term.setPaletteColor or term.setPaletteColour
  if not p then return end
  pcall(p,colors.purple,0.188,0.039,0.141)
  pcall(p,colors.magenta,0.467,0.129,0.435)
  pcall(p,colors.orange,0.914,0.329,0.125)
  pcall(p,colors.gray,0.17,0.17,0.17)
  pcall(p,colors.lightGray,0.68,0.66,0.62)
end

function M.run(ctx)
  tune_palette()
  term.setCursorBlink(false)

  local W,H=term.getSize()
  local canvas=Canvas.new(W,H)
  local windows={}
  local nextId=1
  local active=nil
  local drag=nil
  local overview=false
  local overviewCards={}
  local ctrl,alt=false,false

  local ui={cursor=nil,cursor_y=nil}
  function ui.text(x,y,s,fg,bg) Canvas.put(canvas,x,y,s,fg,bg) end
  function ui.fill(x1,y1,x2,y2,bg,fg,ch) Canvas.fill(canvas,x1,y1,x2,y2,bg,fg,ch) end
  function ui.center(y,s,fg,bg,x1,x2) Canvas.center(canvas,y,s,fg,bg,x1,x2) end

  local function top_visible()
    for i=#windows,1,-1 do
      if not windows[i].minimized then return windows[i] end
    end
    return nil
  end

  local function focus(win)
    if not win then active=nil;return end
    win.minimized=false
    for i=#windows,1,-1 do
      if windows[i]==win then table.remove(windows,i);break end
    end
    windows[#windows+1]=win
    active=win
  end

  local function close(win)
    for i=#windows,1,-1 do
      if windows[i]==win then table.remove(windows,i);break end
    end
    active=top_visible()
  end

  local function minimize(win)
    win.minimized=true
    active=top_visible()
  end

  local function launch(name)
    local spec=APP[name]
    if not spec then return end
    for _,win in ipairs(windows) do
      if win.app==name then focus(win);return end
    end
    local n=#windows
    -- Advanced Computers are only 51x19. Use almost the full workspace
    -- while preserving the GNOME-style dock and top bar.
    local ww=math.max(32,W-7)
    local hh=math.max(11,H-4)
    local x=6+(n%2)
    local y=3+(n%2)
    if x+ww-1>W then x=math.max(5,W-ww) end
    if y+hh-1>H-1 then y=math.max(2,H-hh) end
    local win={
      id=nextId,app=name,title=spec.title,
      x=x,y=y,w=ww,h=hh,max=false,
      state=spec.mod.new(ctx)
    }
    nextId=nextId+1
    windows[#windows+1]=win
    focus(win)
  end

  local function maximize(win)
    if win.max then
      local r=win.restore
      if r then win.x=r.x;win.y=r.y;win.w=r.w;win.h=r.h end
      win.max=false
    else
      win.restore={x=win.x,y=win.y,w=win.w,h=win.h}
      win.x=5;win.y=2;win.w=W-4;win.h=H-1
      win.max=true
    end
  end

  local function app_running(name)
    for _,w in ipairs(windows) do
      if w.app==name then return w end
    end
  end

  local function draw_desktop()
    ui.cursor=nil;ui.cursor_y=nil
    canvas:reset(colors.purple,colors.white)

    ui.fill(1,1,W,1,colors.gray,colors.white)
    ui.text(2,1,overview and "Applications" or "Activities",colors.white,colors.gray)
    local host=(dofile("/usr/lib/cclua/config.lua").machine().hostname or "test-client")
    ui.center(1,host,colors.white,colors.gray)
    local clock=os.date and os.date("%H:%M") or ""
    ui.text(math.max(1,W-#clock-3),1,"N "..clock,colors.white,colors.gray)

    ui.fill(1,2,4,H,colors.black,colors.white)
    local dockIcon={
      terminal={"T",colors.orange},
      files={"F",colors.cyan},
      system={"S",colors.lightGray},
      packages={"A",colors.magenta},
    }
    local dy=3
    for _,name in ipairs(ORDER) do
      local running=app_running(name)
      local icon=dockIcon[name] or {APP[name].icon,colors.white}
      local bg=(running and running==active and not running.minimized) and colors.gray or colors.black
      ui.fill(1,dy,4,dy+2,bg,colors.white)
      ui.center(dy+1,icon[1],icon[2],bg,1,4)
      if running then ui.text(4,dy+1,".",colors.orange,bg) end
      dy=dy+3
    end

    if not overview then
      ui.text(7,3,"Ubuntu 22.04 LTS",colors.lightGray,colors.purple)
      ui.text(7,4,"CCLUA Desktop",colors.orange,colors.purple)
      ui.text(7,H-1,"Activities  |  Ctrl+Alt+T Terminal",colors.lightGray,colors.purple)
    end
  end

  local function draw_overview()
    ui.fill(5,2,W,H,colors.black,colors.white)
    ui.center(2,"Applications",colors.white,colors.black,5,W)

    local cards={
      {name="terminal",label="Terminal",fg=colors.orange},
      {name="files",label="Files",fg=colors.cyan},
      {name="system",label="Settings",fg=colors.lightGray},
      {name="packages",label="Software",fg=colors.magenta},
    }
    local cardW=math.max(16,math.floor((W-8)/2))
    local cardH=4
    for i,card in ipairs(cards) do
      local col=(i-1)%2
      local row=math.floor((i-1)/2)
      local x=6+col*(cardW+1)
      local y=4+row*(cardH+1)
      local x2=math.min(W-1,x+cardW-1)
      ui.fill(x,y,x2,y+cardH-1,colors.gray,colors.white)
      ui.center(y+1,card.label,card.fg,colors.gray,x,x2)
      local running=app_running(card.name)
      if running then
        ui.center(y+2,running.minimized and "minimized" or "running",colors.lime,colors.gray,x,x2)
      end
      card.x1=x;card.x2=x2;card.y1=y;card.y2=y+cardH-1
    end
    ui.text(6,H-1,"Esc closes overview",colors.gray,colors.black)
    return cards
  end

  local function draw_window(win,isActive)
    local titleBg=isActive and colors.gray or colors.black
    local border=isActive and colors.lightGray or colors.gray
    ui.fill(win.x,win.y,win.x+win.w-1,win.y+win.h-1,border,colors.white)
    ui.fill(win.x+1,win.y+1,win.x+win.w-2,win.y+win.h-2,colors.black,colors.white)
    ui.fill(win.x,win.y,win.x+win.w-1,win.y,titleBg,colors.white)

    ui.text(win.x+1,win.y,win.title:sub(1,math.max(1,win.w-12)),colors.white,titleBg)
    ui.text(win.x+win.w-11,win.y,"[-]",colors.lightGray,titleBg)
    ui.text(win.x+win.w-7,win.y,win.max and "[=]" or "[+]",colors.lightGray,titleBg)
    ui.text(win.x+win.w-3,win.y,"[x]",colors.white,colors.red)

    local mod=APP[win.app].mod
    local cx,cy=win.x+1,win.y+1
    local cw,ch=win.w-2,win.h-2
    mod.draw(ctx,win.state,ui,cx,cy,cw,ch,isActive)
  end

  local function render(force)
    draw_desktop()
    if overview then
      overviewCards=draw_overview()
    else
      overviewCards={}
      for _,win in ipairs(windows) do
        if not win.minimized then draw_window(win,win==active) end
      end
    end
    Canvas.flush(canvas,term.current(),force)
    if ui.cursor and active then
      term.setCursorPos(math.max(1,math.min(W,ui.cursor)),math.max(1,math.min(H,ui.cursor_y)))
      term.setCursorBlink(true)
    else term.setCursorBlink(false) end
  end

  local function hit_window(x,y)
    for i=#windows,1,-1 do
      local w=windows[i]
      if not w.minimized and x>=w.x and x<w.x+w.w and y>=w.y and y<w.y+w.h then return w end
    end
  end

  local function route_app(win,ev,a,b,c,x,y)
    local mod=APP[win.app].mod
    local rx=x and (x-(win.x+1)+1) or nil
    local ry=y and (y-(win.y+1)+1) or nil
    return mod.event(ctx,win.state,ev,a,b,c,rx,ry,win.w-2,win.h-2)
  end

  render(true)
  local clockTimer=os.startTimer(1)

  while true do
    local ev,a,b,c=coroutine.yield("wait_event",{
      "mouse_click","mouse_drag","mouse_up","mouse_scroll",
      "key","key_up","char","term_resize","timer","terminate"
    })

    if ev=="terminate" then return 0
    elseif ev=="term_resize" then
      W,H=term.getSize();canvas=Canvas.new(W,H)
      for _,w in ipairs(windows) do if w.max then w.x=5;w.y=2;w.w=W-4;w.h=H-1 end end
      render(true)

    elseif ev=="timer" and a==clockTimer then
      if fs.exists("var/lib/cclua/desktop-reload") then
        fs.delete("var/lib/cclua/desktop-reload")
        return 75
      end
      clockTimer=os.startTimer(1);render(false)

    elseif ev=="key" then
      if a==keys.leftCtrl or a==keys.rightCtrl then ctrl=true end
      if a==keys.leftAlt or a==keys.rightAlt then alt=true end

      if a==keys.escape and overview then
        overview=false
      elseif ctrl and alt and a==keys.t then
        overview=false
        launch("terminal")
      elseif alt and a==keys.tab and #windows>1 then
        for i=#windows-1,1,-1 do
          if not windows[i].minimized then focus(windows[i]);break end
        end
      elseif not overview and active then
        route_app(active,ev,a,b,c)
      end
      render(false)

    elseif ev=="key_up" then
      if a==keys.leftCtrl or a==keys.rightCtrl then ctrl=false end
      if a==keys.leftAlt or a==keys.rightAlt then alt=false end

    elseif ev=="char" then
      if not overview and active then route_app(active,ev,a,b,c) end
      render(false)

    elseif ev=="mouse_click" then
      local button,x,y=a,b,c

      if y==1 and x<=12 then
        overview=not overview
      elseif overview then
        local launched=false
        for _,card in ipairs(overviewCards) do
          if x>=card.x1 and x<=card.x2 and y>=card.y1 and y<=card.y2 then
            overview=false
            launch(card.name)
            launched=true
            break
          end
        end
        if not launched and x<=4 and y>=3 then
          local idx=math.floor((y-3)/3)+1
          local name=ORDER[idx]
          if name then overview=false;launch(name) end
        end
      elseif x<=4 and y>=3 then
        local idx=math.floor((y-3)/3)+1
        local name=ORDER[idx]
        if name then launch(name) end
      else
        local win=hit_window(x,y)
        if win then
          focus(win)
          if y==win.y and x>=win.x+win.w-3 then
            close(win)
          elseif y==win.y and x>=win.x+win.w-7 then
            maximize(win)
          elseif y==win.y and x>=win.x+win.w-11 then
            minimize(win)
          elseif y==win.y and not win.max then
            drag={win=win,mode="move",dx=x-win.x,dy=y-win.y}
          elseif x==win.x+win.w-1 and y==win.y+win.h-1 and not win.max then
            drag={win=win,mode="resize"}
          else
            route_app(win,ev,button,x,y,x,y)
          end
        else active=nil end
      end
      render(false)

    elseif ev=="mouse_drag" and drag then
      local x,y=b,c
      local win=drag.win
      if drag.mode=="move" then
        win.x=math.max(5,math.min(W-win.w+1,x-drag.dx))
        win.y=math.max(2,math.min(H-win.h+1,y-drag.dy))
      else
        win.w=math.max(24,math.min(W-win.x+1,x-win.x+1))
        win.h=math.max(8,math.min(H-win.y+1,y-win.y+1))
      end
      render(false)

    elseif ev=="mouse_up" then drag=nil
    elseif ev=="mouse_scroll" and not overview and active then
      route_app(active,ev,a,b,c,b,c);render(false)
    end
  end
end

return M
