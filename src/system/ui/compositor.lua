local Surface = ISO.require("system/ui/surface.lua")
local M = {}

local function replaceSegment(base, x, value)
  if x < 1 then
    value = value:sub(2 - x); x = 1
  end
  if x > #base or #value == 0 then return base end
  local take = math.min(#value, #base - x + 1)
  value = value:sub(1, take)
  return base:sub(1, x - 1) .. value .. base:sub(x + take)
end

function M.new(display)
  local w, h = display:size()
  local self = {
    display = display,
    width = w, height = h,
    desktop = Surface.new(w, h, colors.white, colors.black),
    windows = {}, nextId = 1,
    last = {}, frame = 0, focused = nil,
  }

  function self:resize()
    local _, nw, nh = display:refreshSize()
    if nw == self.width and nh == self.height then return false end
    self.width, self.height = nw, nh
    self.desktop:resize(nw, nh)
    self.last = {}
    return true
  end

  function self:createWindow(opts)
    opts = opts or {}
    local outerW = math.max(12, math.min(opts.width or 36, self.width))
    local outerH = math.max(6, math.min(opts.height or 14, self.height - 1))
    local win = {
      id = self.nextId,
      title = opts.title or "Window",
      x = math.max(1, math.min(opts.x or 2, self.width - outerW + 1)),
      y = math.max(2, math.min(opts.y or 3, self.height - outerH + 1)),
      width = outerW, height = outerH,
      visible = opts.visible ~= false,
      app = opts.app,
      surface = Surface.new(outerW - 2, outerH - 2, colors.white, colors.black),
    }
    self.nextId = self.nextId + 1
    self.windows[#self.windows + 1] = win
    self.focused = win.id
    return win
  end

  function self:getWindow(id)
    for _, win in ipairs(self.windows) do if win.id == id then return win end end
  end

  function self:raise(id)
    for i, win in ipairs(self.windows) do
      if win.id == id then
        table.remove(self.windows, i)
        self.windows[#self.windows + 1] = win
        self.focused = id
        return true
      end
    end
    return false
  end

  function self:close(id)
    for i, win in ipairs(self.windows) do
      if win.id == id then
        table.remove(self.windows, i)
        if self.focused == id then self.focused = self.windows[#self.windows] and self.windows[#self.windows].id or nil end
        return true
      end
    end
    return false
  end
  local function paint(rows, x, y, text, fg, bg)
    if y < 1 or y > self.height then return end
    local row = rows[y]
    if not row then return end
    row[1] = replaceSegment(row[1], x, text)
    row[2] = replaceSegment(row[2], x, fg)
    row[3] = replaceSegment(row[3], x, bg)
  end

  local function solid(rows, x, y, width, fgColour, bgColour, text)
    local chFg = Surface.toBlit(fgColour)
    local chBg = Surface.toBlit(bgColour)
    local s = text or string.rep(" ", width)
    if #s < width then s = s .. string.rep(" ", width - #s) end
    s = s:sub(1, width)
    paint(rows, x, y, s, string.rep(chFg, width), string.rep(chBg, width))
  end

  function self:compose()
    self:resize()
    local rows = {}
    for y = 1, self.height do
      local t, f, b = self.desktop:getRow(y)
      rows[y] = {t, f, b}
    end

    for _, win in ipairs(self.windows) do
      if win.visible then
        local active = win.id == self.focused
        local titleBg = active and colors.blue or colors.gray
        local borderBg = active and colors.blue or colors.gray
        solid(rows, win.x, win.y, win.width, colors.white, titleBg)
        local title = " " .. win.title
        paint(rows, win.x, win.y, title:sub(1, math.max(0, win.width - 4)),
          string.rep(Surface.toBlit(colors.white), math.min(#title, math.max(0,win.width-4))),
          string.rep(Surface.toBlit(titleBg), math.min(#title, math.max(0,win.width-4))))
        solid(rows, win.x + win.width - 2, win.y, 2, colors.white, colors.red, "x ")
        for yy = 1, win.height - 2 do
          local sy = win.y + yy
          solid(rows, win.x, sy, 1, colors.white, borderBg)
          solid(rows, win.x + win.width - 1, sy, 1, colors.white, borderBg)
          local t, f, b = win.surface:getRow(yy)
          paint(rows, win.x + 1, sy, t, f, b)
        end
        solid(rows, win.x, win.y + win.height - 1, win.width, colors.white, borderBg)
      end
    end
    return rows
  end

  function self:present(force)
    local rows = self:compose()
    local changed = 0
    for y = 1, self.height do
      local row, old = rows[y], self.last[y]
      if force or not old or row[1] ~= old[1] or row[2] ~= old[2] or row[3] ~= old[3] then
        display:blitLine(y, row[1], row[2], row[3])
        self.last[y] = {row[1], row[2], row[3]}
        changed = changed + 1
      end
    end
    self.frame = self.frame + 1
    return changed
  end

  function self:windowAt(x, y)
    for i = #self.windows, 1, -1 do
      local win = self.windows[i]
      if win.visible and x >= win.x and x < win.x + win.width and
         y >= win.y and y < win.y + win.height then return win end
    end
    return nil
  end

  return self
end

return M
