local M = {}

local DEFAULT_PALETTE = {
  [colors.white]     = {0.93, 0.95, 0.98},
  [colors.orange]    = {0.95, 0.45, 0.15},
  [colors.magenta]   = {0.78, 0.32, 0.86},
  [colors.lightBlue] = {0.25, 0.62, 0.95},
  [colors.yellow]    = {0.98, 0.78, 0.18},
  [colors.lime]      = {0.30, 0.80, 0.34},
  [colors.pink]      = {0.95, 0.40, 0.62},
  [colors.gray]      = {0.16, 0.18, 0.22},
  [colors.lightGray] = {0.48, 0.52, 0.60},
  [colors.cyan]      = {0.15, 0.78, 0.88},
  [colors.purple]    = {0.48, 0.34, 0.82},
  [colors.blue]      = {0.12, 0.30, 0.66},
  [colors.brown]     = {0.42, 0.25, 0.13},
  [colors.green]     = {0.10, 0.48, 0.28},
  [colors.red]       = {0.90, 0.20, 0.23},
  [colors.black]     = {0.025, 0.032, 0.045},
}

local function pickTarget()
  local monitor = peripheral and peripheral.find and peripheral.find("monitor")
  if monitor then
    pcall(monitor.setTextScale, 0.5)
    return monitor, "monitor"
  end
  return (term.native and term.native() or term.current()), "terminal"
end
function M.open()
  local target, kind = pickTarget()
  local self = { target = target, kind = kind, palette = {}, frames = 0 }
  local w, h = target.getSize()
  self.width, self.height = w, h

  for colour, rgb in pairs(DEFAULT_PALETTE) do
    if target.setPaletteColor then
      pcall(target.setPaletteColor, colour, rgb[1], rgb[2], rgb[3])
    end
    self.palette[colour] = {rgb[1], rgb[2], rgb[3]}
  end
  target.setCursorBlink(false)
  target.setBackgroundColor(colors.black)
  target.clear()

  function self:size()
    local nw, nh = target.getSize()
    self.width, self.height = nw, nh
    return nw, nh
  end

  function self:blitLine(y, text, fg, bg)
    if y < 1 or y > self.height then return end
    target.setCursorPos(1, y)
    target.blit(text, fg, bg)
  end

  function self:setPalette(colour, r, g, b)
    if not target.setPaletteColor then return false end
    target.setPaletteColor(colour, r, g, b)
    self.palette[colour] = {r, g, b}
    return true
  end
  function self:clear()
    target.setBackgroundColor(colors.black)
    target.clear()
  end

  function self:cursor(x, y, blink, colour)
    target.setCursorPos(x or 1, y or 1)
    if colour then target.setTextColor(colour) end
    target.setCursorBlink(not not blink)
  end

  function self:refreshSize()
    local nw, nh = target.getSize()
    local changed = nw ~= self.width or nh ~= self.height
    self.width, self.height = nw, nh
    return changed, nw, nh
  end

  function self:isColor()
    return target.isColor and target.isColor() or false
  end

  return self
end

return M
