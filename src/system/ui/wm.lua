local M = {}

function M.new(compositor)
  local function mapPoint(x,y)
    local display=compositor.display
    if display and display.mapInput then return display:mapInput(x,y) end
    return x,y
  end

  local self = {
    compositor = compositor,
    apps = {},
    dragging = nil,
    desktopHandler = nil,
    running = true,
  }

  function self:setDesktopHandler(handler)
    self.desktopHandler = handler
  end

  function self:attach(win, app)
    self.apps[win.id] = app
    win.app = app
    if app and app.draw then app.draw(win) end
    return win
  end

  function self:open(opts, app)
    return self:attach(compositor:createWindow(opts), app)
  end

  function self:close(id)
    local app = self.apps[id]
    if app and app.close then pcall(app.close) end
    self.apps[id] = nil
    return compositor:close(id)
  end

  local function clampWindow(win)
    win.x = math.max(1, math.min(win.x, math.max(1, compositor.width - win.width + 1)))
    win.y = math.max(2, math.min(win.y, math.max(2, compositor.height - win.height + 1)))
  end

  function self:redrawAll()
    for _, win in ipairs(compositor.windows) do
      local app = self.apps[win.id]
      if app and app.draw then app.draw(win) end
    end
    compositor:present()
  end
  local function routeToWindow(win, event, ...)
    local app = win and self.apps[win.id]
    if app and app.event then
      local ok, err = pcall(app.event, event, ...)
      if not ok then
        win.surface:clear(colors.black, colors.white)
        win.surface:write(2,2,"Application error",colors.red)
        win.surface:write(2,4,tostring(err):sub(1, win.surface.width - 2),colors.lightGray)
      end
    end
  end

  function self:handle(event, a, b, c, d, e)
    if event == "term_resize" or event == "monitor_resize" then
      compositor:resize()
      for _, win in ipairs(compositor.windows) do clampWindow(win) end
      if self.desktopHandler and self.desktopHandler.resize then
        self.desktopHandler.resize(compositor.width, compositor.height)
      end
      self:redrawAll()
      return
    end

    if event == "mouse_click" then
      local button, x, y = a, b, c
      x,y=mapPoint(x,y)
      local win = compositor:windowAt(x,y)
      if win then
        compositor:raise(win.id)
        if y == win.y and x >= win.x + win.width - 2 then
          self:close(win.id)
        elseif y == win.y and x >= win.x + win.width - 5 then
          compositor:minimize(win.id)
          if self.desktopHandler and self.desktopHandler.draw then self.desktopHandler.draw() end
        elseif y == win.y then
          self.dragging = { id=win.id, dx=x-win.x, dy=y-win.y }
        else
          routeToWindow(win, event, button, x-win.x, y-win.y)
        end
      elseif self.desktopHandler and self.desktopHandler.event then
        self.desktopHandler.event(event, button, x, y)
      end
      compositor:present()
      return
    end
    if event == "mouse_drag" and self.dragging then
      local mx,my=mapPoint(b,c)
      local win = compositor:getWindow(self.dragging.id)
      if win then
        win.x = mx - self.dragging.dx
        win.y = my - self.dragging.dy
        clampWindow(win)
      end
      compositor:present()
      return
    elseif event == "mouse_up" then
      self.dragging = nil
      return
    elseif event == "monitor_touch" then
      local x, y = b, c
      x,y=mapPoint(x,y)
      local win = compositor:windowAt(x,y)
      if win then
        compositor:raise(win.id)
        if y == win.y and x >= win.x + win.width - 2 then
          self:close(win.id)
        else
          routeToWindow(win, "mouse_click", 1, x-win.x, y-win.y)
        end
      elseif self.desktopHandler and self.desktopHandler.event then
        self.desktopHandler.event("mouse_click",1,x,y)
      end
      compositor:present()
      return
    end

    local focused = compositor.focused and compositor:getWindow(compositor.focused)
    if focused then routeToWindow(focused, event, a, b, c, d, e) end
    if self.desktopHandler and self.desktopHandler.event then
      self.desktopHandler.event(event, a, b, c, d, e)
    end
    compositor:present()
  end

  function self:run()
    compositor:present(true)
    while self.running do
      self:handle(os.pullEventRaw())
    end
  end

  function self:stop()
    self.running = false
  end

  return self
end

return M
