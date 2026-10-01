local M={}

function M.new(ctx)
  local self={ctx=ctx,timer=nil}
  local desktop=ctx.compositor.desktop

  local function clock()
    if textutils and textutils.formatTime then return textutils.formatTime(os.time(),true) end
    return "--:--"
  end

  function self.draw()
    local w,h=ctx.compositor.width,ctx.compositor.height
    desktop:resize(w,h)
    desktop:clear(colors.black,colors.white)

    -- Top system bar
    desktop:fill(1,1,w,1," ",colors.white,colors.gray)
    desktop:write(2,1,"CCLUA",colors.cyan,colors.gray)
    desktop:write(8,1,ctx.config.version,colors.lightGray,colors.gray)
    local t=clock()
    desktop:write(math.max(1,w-#t-1),1,t,colors.white,colors.gray)

    -- Desktop brand and quick actions
    if h>=8 then
      desktop:write(3,4,ctx.config.name,colors.cyan,colors.black)
      desktop:write(3,5,ctx.config.codename.."  //  "..ctx.config.build,colors.lightGray,colors.black)
    end

    -- Dock
    desktop:fill(1,h,w,1," ",colors.white,colors.gray)
    desktop:write(2,h,"[T] Terminal",colors.white,colors.gray)
    desktop:write(16,h,"[F] Files",colors.white,colors.gray)
    desktop:write(27,h,"[S] Settings",colors.white,colors.gray)
    desktop:write(math.max(42,w-12),h,"Apps",colors.cyan,colors.gray)
  end
  function self.resize()
    self.draw()
  end

  function self.event(event,a,b,c)
    if event=="mouse_click" then
      local _,x,y=a,b,c
      if y==ctx.compositor.height then
        if x>=2 and x<=13 then ctx.openApp("terminal")
        elseif x>=16 and x<=24 then ctx.openApp("files")
        elseif x>=27 and x<=38 then ctx.openApp("settings") end
      end
    elseif event=="timer" and a==self.timer then
      self.draw()
      self.timer=os.startTimer(1)
    elseif event=="key" then
      if a==keys.t and (keys.getName and keys.getName(a)=="t") then
        -- Reserved for future global shortcuts.
      end
    end
  end

  function self.start()
    self.draw()
    self.timer=os.startTimer(1)
  end

  return self
end

return M
