local Canvas=dofile("/usr/lib/cclua/desktop/canvas.lua")
local Config=dofile("/usr/lib/cclua/config.lua")
local Terminal=dofile("/usr/lib/cclua/desktop/apps/terminal.lua")
local Files=dofile("/usr/lib/cclua/desktop/apps/files.lua")
local Editor=dofile("/usr/lib/cclua/desktop/apps/editor.lua")
local Monitor=dofile("/usr/lib/cclua/desktop/apps/monitor.lua")
local System=dofile("/usr/lib/cclua/desktop/apps/system.lua")
local Packages=dofile("/usr/lib/cclua/desktop/apps/packages.lua")

local M={}

local APP={
  terminal={title="Terminal",icon=">_",color=colors.orange,mod=Terminal},
  files={title="Files",icon="[]",color=colors.cyan,mod=Files},
  editor={title="Text Editor",icon="Ed",color=colors.lime,mod=Editor},
  monitor={title="System Monitor",icon="Mo",color=colors.yellow,mod=Monitor},
  system={title="Settings",icon="St",color=colors.lightGray,mod=System},
  packages={title="Software",icon="SW",color=colors.magenta,mod=Packages},
}
local ORDER={"terminal","files","editor","monitor","system","packages"}
local SESSION_PATH="home/caden/.config/cclua-desktop/session.json"

local function tune_palette()
  local p=term.setPaletteColor or term.setPaletteColour
  if not p then return end
  pcall(p,colors.purple,0.16,0.025,0.12)
  pcall(p,colors.magenta,0.46,0.08,0.38)
  pcall(p,colors.orange,0.91,0.28,0.08)
  pcall(p,colors.gray,0.12,0.12,0.13)
  pcall(p,colors.lightGray,0.68,0.67,0.65)
  pcall(p,colors.blue,0.08,0.04,0.14)
  pcall(p,colors.cyan,0.18,0.72,0.82)
  pcall(p,colors.lime,0.36,0.78,0.28)
  pcall(p,colors.yellow,0.95,0.72,0.18)
end

local function read_json(path)
  local ok,h=pcall(fs.open,path,"r")
  if not ok or not h then return nil end
  local raw=h.readAll();h.close()
  local good,data=pcall(textutils.unserializeJSON,raw)
  if good and type(data)=="table" then return data end
end

local function write_json(path,value)
  local dir=fs.getDir(path)
  if dir~="" and not fs.exists(dir) then pcall(fs.makeDir,dir) end
  local ok,h=pcall(fs.open,path,"w")
  if not ok or not h then return false end
  h.write(textutils.serializeJSON(value))
  h.close()
  return true
end

function M.run(ctx)
  tune_palette()
  term.setCursorBlink(false)

  local machine=Config.machine()
  local W,H=term.getSize()
  local canvas=Canvas.new(W,H)
  local windows={}
  local nextId=1
  local active=nil
  local drag=nil
  local overview=false
  local overviewQuery=""
  local overviewCards={}
  local systemMenu=false
  local systemMenuBox=nil
  local ctrl,alt=false,false
  local restoring=true
  local updateCache={}
  local updateCacheAt=0

  local ui={cursor=nil,cursor_y=nil}
  function ui.text(x,y,s,fg,bg) Canvas.put(canvas,x,y,s,fg,bg) end
  function ui.fill(x1,y1,x2,y2,bg,fg,ch) Canvas.fill(canvas,x1,y1,x2,y2,bg,fg,ch) end
  function ui.center(y,s,fg,bg,x1,x2) Canvas.center(canvas,y,s,fg,bg,x1,x2) end

  local function update_state()
    local now=os.epoch and os.epoch("utc") or 0
    if now-updateCacheAt>2000 then
      updateCache=Config.read_json("/var/lib/cclua/update-state.json",{}) or {}
      updateCacheAt=now
    end
    return updateCache
  end

  local function top_visible()
    for i=#windows,1,-1 do
      if not windows[i].minimized then return windows[i] end
    end
  end

  local function snapshot_window(win)
    local state=nil
    local spec=APP[win.app]
    if spec and spec.mod.snapshot then
      local ok,value=pcall(spec.mod.snapshot,win.state)
      if ok and type(value)=="table" then state=value end
    end
    return {
      app=win.app,x=win.x,y=win.y,w=win.w,h=win.h,
      max=win.max==true,minimized=win.minimized==true,state=state
    }
  end

  local function save_session()
    if restoring then return end
    local out={schema=1,windows={},active=active and active.app or nil}
    for _,win in ipairs(windows) do out.windows[#out.windows+1]=snapshot_window(win) end
    write_json(SESSION_PATH,out)
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
    save_session()
  end

  local function minimize(win)
    win.minimized=true
    active=top_visible()
    save_session()
  end

  local function launch(name,opts,noSave)
    local spec=APP[name]
    if not spec then return nil end

    for _,win in ipairs(windows) do
      if win.app==name then
        if opts and spec.mod.open then pcall(spec.mod.open,ctx,win.state,opts) end
        focus(win)
        if not noSave then save_session() end
        return win
      end
    end

    local n=#windows
    -- The Advanced Computer is only 51x19. Keep the dock visible, but give
    -- applications almost the entire remaining workspace.
    local ww=math.max(34,W-5)
    local hh=math.max(11,H-3)
    local x=4+(n%2)
    local y=2+(n%2)
    if x+ww-1>W then x=math.max(4,W-ww+1) end
    if y+hh-1>H then y=math.max(2,H-hh+1) end

    local state=spec.mod.new(ctx,opts or {})
    local win={
      id=nextId,app=name,title=spec.title,
      x=x,y=y,w=ww,h=hh,max=false,minimized=false,
      restore=nil,state=state
    }
    nextId=nextId+1
    windows[#windows+1]=win
    focus(win)
    if not noSave then save_session() end
    return win
  end

  local function maximize(win)
    if win.max then
      local r=win.restore
      if r then win.x=r.x;win.y=r.y;win.w=r.w;win.h=r.h end
      win.max=false
    else
      win.restore={x=win.x,y=win.y,w=win.w,h=win.h}
      win.x=4;win.y=2;win.w=W-3;win.h=H-1
      win.max=true
    end
    save_session()
  end

  local function app_running(name)
    for _,win in ipairs(windows) do
      if win.app==name then return win end
    end
  end

  local function restore_session()
    local data=read_json(SESSION_PATH)
    if type(data)=="table" and type(data.windows)=="table" then
      for _,item in ipairs(data.windows) do
        if APP[item.app] then
          local win=launch(item.app,item.state,true)
          if win then
            win.x=math.max(4,math.min(W-10,tonumber(item.x) or win.x))
            win.y=math.max(2,math.min(H-5,tonumber(item.y) or win.y))
            win.w=math.max(24,math.min(W-win.x+1,tonumber(item.w) or win.w))
            win.h=math.max(8,math.min(H-win.y+1,tonumber(item.h) or win.h))
            win.minimized=item.minimized==true
            if item.max==true then
              win.restore={x=win.x,y=win.y,w=win.w,h=win.h}
              win.x=4;win.y=2;win.w=W-3;win.h=H-1;win.max=true
            end
          end
        end
      end
      if data.active then
        local win=app_running(data.active)
        if win and not win.minimized then focus(win) end
      end
      active=top_visible()
    end
    restoring=false
  end

  local function draw_wallpaper()
    canvas:reset(colors.purple,colors.white)
    ui.fill(4,2,W,H,colors.purple,colors.white)

    -- Simple low-resolution interpretation of Ubuntu's aubergine wallpaper:
    -- a dark field with two diagonal magenta planes.
    for yy=2,H do
      local start1=math.max(4,W-9-math.floor((yy-2)*0.55))
      local start2=math.max(4,W-3-math.floor((yy-2)*0.28))
      ui.fill(start1,yy,W,yy,colors.magenta,colors.white)
      ui.fill(start2,yy,W,yy,colors.purple,colors.white)
    end

    ui.text(6,4,"Ubuntu 22.04 LTS",colors.lightGray,colors.purple)
    ui.text(6,5,"CCLUA Desktop",colors.orange,colors.purple)
  end

  local function draw_dock()
    ui.fill(1,2,3,H,colors.black,colors.white)
    local dy=3
    for _,name in ipairs(ORDER) do
      local spec=APP[name]
      local running=app_running(name)
      local selected=running and running==active and not running.minimized
      local bg=selected and colors.gray or colors.black
      ui.fill(1,dy,3,dy+1,bg,colors.white)
      ui.center(dy,spec.icon,spec.color,bg,1,3)
      if running then
        ui.center(dy+1,running.minimized and "-" or ".",colors.orange,bg,1,3)
      end
      dy=dy+2
      if dy>H-1 then break end
    end
  end

  local function draw_panel()
    ui.fill(1,1,W,1,colors.gray,colors.white)
    ui.text(2,1,overview and "Applications" or "Activities",colors.white,colors.gray)

    local centerText=active and active.title or (machine.hostname or "test-client")
    ui.center(1,centerText:sub(1,20),colors.white,colors.gray)

    local clock=os.date and os.date("%H:%M") or ""
    local net=(machine.address and machine.address~="") and "N" or "X"
    local right=net.." "..clock
    ui.text(math.max(1,W-#right-1),1,right,colors.white,colors.gray)
  end

  local function draw_overview()
    ui.fill(4,2,W,H,colors.black,colors.white)
    ui.center(2,"Applications",colors.white,colors.black,4,W)

    local searchText=overviewQuery=="" and "Type to search..." or overviewQuery
    local searchFg=overviewQuery=="" and colors.gray or colors.white
    ui.fill(6,3,W-3,3,colors.gray,colors.white)
    ui.text(8,3,searchText:sub(1,math.max(1,W-12)),searchFg,colors.gray)

    local filtered={}
    local q=overviewQuery:lower()
    for _,name in ipairs(ORDER) do
      local spec=APP[name]
      if q=="" or name:lower():find(q,1,true) or spec.title:lower():find(q,1,true) then
        filtered[#filtered+1]=name
      end
    end

    local cards={}
    local cardW=math.max(14,math.floor((W-7)/2))
    local cardH=3
    for i,name in ipairs(filtered) do
      local spec=APP[name]
      local col=(i-1)%2
      local row=math.floor((i-1)/2)
      local x=5+col*(cardW+1)
      local y=5+row*(cardH+1)
      if y+cardH-1<=H-2 then
        local x2=math.min(W-1,x+cardW-1)
        ui.fill(x,y,x2,y+cardH-1,colors.gray,colors.white)
        ui.text(x+1,y,spec.icon,spec.color,colors.gray)
        ui.center(y+1,spec.title,colors.white,colors.gray,x,x2)
        local running=app_running(name)
        if running then
          ui.center(y+2,running.minimized and "minimized" or "running",colors.lime,colors.gray,x,x2)
        end
        cards[#cards+1]={name=name,x1=x,x2=x2,y1=y,y2=y+cardH-1}
      end
    end

    if #cards==0 then
      ui.center(8,"No applications found",colors.gray,colors.black,4,W)
    end
    ui.text(5,H-1,"Enter launch  Esc close  Backspace edit",colors.gray,colors.black)
    return cards
  end

  local function draw_system_menu()
    local update=update_state()
    local width=math.min(27,W-6)
    local x1=W-width+1
    local x2=W
    local y1=2
    local y2=math.min(H,10)

    ui.fill(x1,y1,x2,y2,colors.black,colors.white)
    ui.fill(x1,y1,x2,y1,colors.gray,colors.white)
    ui.text(x1+1,y1,"System",colors.white,colors.gray)

    local rows={
      {"Network",machine.address or "offline",colors.cyan},
      {"Update",tostring(update.state or "UNKNOWN"),update.state=="CURRENT" and colors.lime or colors.orange},
      {"Image",tostring(update.current_commit or "?"):sub(1,14),colors.lightGray},
      {"User","caden",colors.white},
    }
    local yy=y1+2
    for _,row in ipairs(rows) do
      if yy>=y2 then break end
      ui.text(x1+1,yy,row[1],colors.gray,colors.black)
      local val=tostring(row[2])
      local vx=math.max(x1+9,x2-#val-1)
      ui.text(vx,yy,val:sub(1,math.max(1,x2-vx)),row[3],colors.black)
      yy=yy+1
    end

    ui.fill(x1+1,y2-1,x2-1,y2-1,colors.gray,colors.white)
    ui.center(y2-1,"Reload Desktop",colors.white,colors.gray,x1+1,x2-1)
    systemMenuBox={x1=x1,x2=x2,y1=y1,y2=y2,reloadY=y2-1}
  end

  local function draw_window(win,isActive)
    local titleBg=isActive and colors.gray or colors.black
    local border=isActive and colors.gray or colors.black
    ui.fill(win.x,win.y,win.x+win.w-1,win.y+win.h-1,border,colors.white)
    ui.fill(win.x+1,win.y+1,win.x+win.w-2,win.y+win.h-2,colors.black,colors.white)
    ui.fill(win.x,win.y,win.x+win.w-1,win.y,titleBg,colors.white)

    local titleRight=win.x+win.w-13
    if titleRight>win.x then
      ui.center(win.y,win.title:sub(1,math.max(1,win.w-14)),colors.white,titleBg,win.x+1,titleRight)
    end
    ui.text(win.x+win.w-11,win.y,"[-]",colors.lightGray,titleBg)
    ui.text(win.x+win.w-7,win.y,win.max and "[=]" or "[+]",colors.lightGray,titleBg)
    ui.text(win.x+win.w-3,win.y,"[x]",colors.white,colors.red)

    local spec=APP[win.app]
    if not spec then return end
    local cx,cy=win.x+1,win.y+1
    local cw,ch=win.w-2,win.h-2
    spec.mod.draw(ctx,win.state,ui,cx,cy,cw,ch,isActive)
  end

  local function render(force)
    ui.cursor=nil;ui.cursor_y=nil
    draw_wallpaper()
    draw_dock()
    draw_panel()

    if overview then
      overviewCards=draw_overview()
    else
      overviewCards={}
      for _,win in ipairs(windows) do
        if not win.minimized then draw_window(win,win==active) end
      end
    end

    if systemMenu then draw_system_menu() else systemMenuBox=nil end

    Canvas.flush(canvas,term.current(),force)
    if ui.cursor and active and not overview and not systemMenu then
      term.setCursorPos(
        math.max(1,math.min(W,ui.cursor)),
        math.max(1,math.min(H,ui.cursor_y))
      )
      term.setCursorBlink(true)
    else
      term.setCursorBlink(false)
    end
  end

  local function hit_window(x,y)
    for i=#windows,1,-1 do
      local win=windows[i]
      if not win.minimized
        and x>=win.x and x<win.x+win.w
        and y>=win.y and y<win.y+win.h then
        return win
      end
    end
  end

  local function handle_action(result)
    if type(result)~="table" then return result end
    if result.action=="open_app" and result.app then
      launch(result.app,result)
      return true
    end
    return result
  end

  local function route_app(win,ev,a,b,c,x,y)
    if not win or not APP[win.app] then return false end
    local mod=APP[win.app].mod
    local rx=x and (x-(win.x+1)+1) or nil
    local ry=y and (y-(win.y+1)+1) or nil
    return handle_action(mod.event(ctx,win.state,ev,a,b,c,rx,ry,win.w-2,win.h-2))
  end

  local function dock_app_at(y)
    if y<3 then return nil end
    local idx=math.floor((y-3)/2)+1
    return ORDER[idx]
  end

  restore_session()
  render(true)
  local clockTimer=os.startTimer(1)

  while true do
    local ev,a,b,c=coroutine.yield("wait_event",{
      "mouse_click","mouse_drag","mouse_up","mouse_scroll",
      "key","key_up","char","term_resize","timer","terminate"
    })

    if ev=="terminate" then
      save_session()
      return 0

    elseif ev=="term_resize" then
      W,H=term.getSize()
      canvas=Canvas.new(W,H)
      for _,win in ipairs(windows) do
        if win.max then
          win.x=4;win.y=2;win.w=W-3;win.h=H-1
        else
          win.x=math.max(4,math.min(W-win.w+1,win.x))
          win.y=math.max(2,math.min(H-win.h+1,win.y))
        end
      end
      save_session()
      render(true)

    elseif ev=="timer" and a==clockTimer then
      if fs.exists("var/lib/cclua/desktop-reload") then
        fs.delete("var/lib/cclua/desktop-reload")
        save_session()
        return 75
      end
      clockTimer=os.startTimer(1)
      render(false)

    elseif ev=="key" then
      if a==keys.leftCtrl or a==keys.rightCtrl then ctrl=true end
      if a==keys.leftAlt or a==keys.rightAlt then alt=true end

      if a==keys.escape then
        if systemMenu then systemMenu=false
        elseif overview then overview=false;overviewQuery=""
        elseif active then active=nil end
      elseif overview and a==keys.backspace then
        overviewQuery=overviewQuery:sub(1,-2)
      elseif overview and a==keys.enter then
        local first=overviewCards[1]
        if first then
          overview=false
          overviewQuery=""
          launch(first.name)
        end
      elseif ctrl and alt and a==keys.t then
        overview=false;overviewQuery="";systemMenu=false
        launch("terminal")
      elseif ctrl and a==keys.l and active and active.app=="terminal" then
        active.state.lines={}
      elseif alt and a==keys.tab and #windows>1 then
        for i=#windows-1,1,-1 do
          if not windows[i].minimized then focus(windows[i]);break end
        end
      elseif not overview and not systemMenu and active then
        route_app(active,ev,a,b,c)
      end
      render(false)

    elseif ev=="key_up" then
      if a==keys.leftCtrl or a==keys.rightCtrl then ctrl=false end
      if a==keys.leftAlt or a==keys.rightAlt then alt=false end
      if not overview and not systemMenu and active then
        route_app(active,ev,a,b,c)
      end

    elseif ev=="char" then
      if overview then
        overviewQuery=overviewQuery..tostring(a)
      elseif not systemMenu and active then
        route_app(active,ev,a,b,c)
      end
      render(false)

    elseif ev=="mouse_click" then
      local button,x,y=a,b,c

      if y==1 and x<=12 then
        if overview then
          overview=false
          overviewQuery=""
        else
          overview=true
          overviewQuery=""
        end
        systemMenu=false
      elseif y==1 and x>=W-10 then
        systemMenu=not systemMenu
        overview=false
        overviewQuery=""
      elseif systemMenu then
        if systemMenuBox
          and x>=systemMenuBox.x1 and x<=systemMenuBox.x2
          and y==systemMenuBox.reloadY then
          systemMenu=false
          save_session()
          return 75
        end
        if not systemMenuBox
          or x<systemMenuBox.x1 or x>systemMenuBox.x2
          or y<systemMenuBox.y1 or y>systemMenuBox.y2 then
          systemMenu=false
        end

      elseif overview then
        local launched=false
        for _,card in ipairs(overviewCards) do
          if x>=card.x1 and x<=card.x2 and y>=card.y1 and y<=card.y2 then
            overview=false
            overviewQuery=""
            launch(card.name)
            launched=true
            break
          end
        end
        if not launched and x<=3 then
          local name=dock_app_at(y)
          if name then overview=false;launch(name) end
        end

      elseif x<=3 then
        local name=dock_app_at(y)
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
        else
          active=nil
        end
      end
      render(false)

    elseif ev=="mouse_drag" and drag then
      local x,y=b,c
      local win=drag.win
      if drag.mode=="move" then
        win.x=math.max(4,math.min(W-win.w+1,x-drag.dx))
        win.y=math.max(2,math.min(H-win.h+1,y-drag.dy))
      else
        win.w=math.max(24,math.min(W-win.x+1,x-win.x+1))
        win.h=math.max(8,math.min(H-win.y+1,y-win.y+1))
      end
      render(false)

    elseif ev=="mouse_up" then
      if drag then save_session() end
      drag=nil

    elseif ev=="mouse_scroll" and not overview and not systemMenu and active then
      route_app(active,ev,a,b,c,b,c)
      render(false)
    end
  end
end

return M
