local M={}

function M.new(ctx)
  local self={ctx=ctx,timer=nil,taskHits={}}
  local desktop=ctx.compositor.desktop

  local function palette()
    return ctx.theme and ctx.theme:palette() or ctx.config.theme or {}
  end

  local function clock()
    if textutils and textutils.formatTime then return textutils.formatTime(os.time(),true) end
    return "--:--"
  end

  local function taskWindows()
    local out={}
    for _,win in ipairs(ctx.compositor.windows) do out[#out+1]=win end
    return out
  end

  local function shortcut(surface,x,y,label,key,p)
    local text=" "..key.."  "..label.." "
    surface:write(x,y,text,p.text or colors.white,p.panelAlt or colors.gray)
    return x+#text
  end

  function self.draw()
    local w,h=ctx.compositor.width,ctx.compositor.height
    local p=palette()
    desktop:resize(w,h)
    desktop:clear(p.background or colors.black,p.text or colors.white)

    desktop:fill(1,1,w,1," ",p.text or colors.white,p.panel or colors.gray)
    desktop:write(2,1,"CCLUA",p.accent or colors.cyan,p.panel or colors.gray)
    desktop:write(8,1,ctx.config.version,p.muted or colors.lightGray,p.panel or colors.gray)
    local themeName=ctx.theme and ctx.theme:status().name or "Default"
    local right=themeName.."  "..clock()
    desktop:write(math.max(1,w-#right-1),1,right,p.text or colors.white,p.panel or colors.gray)

    if h>=9 then
      desktop:write(3,4,ctx.config.name,p.accent or colors.cyan,p.background or colors.black)
      desktop:write(3,5,ctx.config.codename.." / "..ctx.config.build,p.muted or colors.lightGray,p.background or colors.black)
      desktop:write(3,7,"Modern Lua workstation",p.text or colors.white,p.background or colors.black)
      desktop:write(3,8,"Apps run as isolated scheduled processes.",p.muted or colors.lightGray,p.background or colors.black)
    end

    self.taskHits={}
    desktop:fill(1,h,w,1," ",p.text or colors.white,p.panel or colors.gray)
    local x=2
    x=shortcut(desktop,x,h,"Terminal","T",p)+1
    x=shortcut(desktop,x,h,"Files","F",p)+1
    x=shortcut(desktop,x,h,"Settings","S",p)+1

    local windows=taskWindows()
    if #windows>0 and x<w-2 then
      desktop:write(x,h,"|",p.muted or colors.lightGray,p.panel or colors.gray)
      x=x+2
      for _,win in ipairs(windows) do
        if x>w-5 then break end
        local maxLen=math.max(3,math.min(10,w-x-1))
        local name=(win.title or "App"):sub(1,maxLen)
        local text=" "..name.." "
        local bg=(win.id==ctx.compositor.focused and win.visible) and (p.accentDim or colors.blue) or (p.panel or colors.gray)
        desktop:write(x,h,text,p.text or colors.white,bg)
        self.taskHits[#self.taskHits+1]={x1=x,x2=x+#text-1,id=win.id}
        x=x+#text+1
      end
    end
  end

  function self.resize()
    self.draw()
  end

  function self.event(event,a,b,c)
    if event=="mouse_click" then
      local _,x,y=a,b,c
      if y==ctx.compositor.height then
        for _,hit in ipairs(self.taskHits) do
          if x>=hit.x1 and x<=hit.x2 then
            local win=ctx.compositor:getWindow(hit.id)
            if win then
              if win.minimized or not win.visible then
                ctx.compositor:restore(win.id)
              elseif ctx.compositor.focused==win.id then
                ctx.compositor:minimize(win.id)
              else
                ctx.compositor:raise(win.id)
              end
              self.draw()
              return
            end
          end
        end
        if x>=2 and x<=14 then ctx.openApp("terminal")
        elseif x>=16 and x<=26 then ctx.openApp("files")
        elseif x>=28 and x<=41 then ctx.openApp("settings") end
        self.draw()
      end
    elseif event=="timer" and a==self.timer then
      self.draw()
      self.timer=os.startTimer(1)
    elseif event=="cclua_theme_changed" then
      self.draw()
      if ctx.wm then ctx.wm:redrawAll() end
    end
  end

  function self.start()
    self.draw()
    self.timer=os.startTimer(1)
  end

  return self
end

return M
