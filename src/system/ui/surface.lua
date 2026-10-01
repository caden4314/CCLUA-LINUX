local M = {}
local HEX = {
  [colors.white]="0",[colors.orange]="1",[colors.magenta]="2",[colors.lightBlue]="3",
  [colors.yellow]="4",[colors.lime]="5",[colors.pink]="6",[colors.gray]="7",
  [colors.lightGray]="8",[colors.cyan]="9",[colors.purple]="a",[colors.blue]="b",
  [colors.brown]="c",[colors.green]="d",[colors.red]="e",[colors.black]="f",
}

local function h(colour)
  return HEX[colour] or "0"
end

function M.new(width, height, fg, bg)
  local self = {
    width = width, height = height,
    fg = fg or colors.white, bg = bg or colors.black,
    rows = {}, dirty = {},
  }

  local function blankRow()
    return {
      string.rep(" ", self.width),
      string.rep(h(self.fg), self.width),
      string.rep(h(self.bg), self.width),
    }
  end

  for y = 1, height do self.rows[y] = blankRow(); self.dirty[y] = true end

  function self:resize(w, ht)
    if w == self.width and ht == self.height then return false end
    local old = self.rows
    self.width, self.height, self.rows, self.dirty = w, ht, {}, {}
    for y = 1, ht do
      local row = blankRow()
      if old[y] then
        local n = math.min(#old[y][1], w)
        row[1] = old[y][1]:sub(1,n) .. row[1]:sub(n+1)
        row[2] = old[y][2]:sub(1,n) .. row[2]:sub(n+1)
        row[3] = old[y][3]:sub(1,n) .. row[3]:sub(n+1)
      end
      self.rows[y] = row; self.dirty[y] = true
    end
    return true
  end

  function self:clear(bgColour, fgColour)
    if bgColour then self.bg = bgColour end
    if fgColour then self.fg = fgColour end
    for y = 1, self.height do
      self.rows[y] = blankRow()
      self.dirty[y] = true
    end
  end

  function self:blit(x, y, text, fgStr, bgStr)
    if y < 1 or y > self.height or x > self.width then return end
    text = tostring(text or "")
    if #text == 0 then return end
    fgStr = fgStr or string.rep(h(self.fg), #text)
    bgStr = bgStr or string.rep(h(self.bg), #text)
    local sourceStart = 1
    if x < 1 then sourceStart = 2 - x; x = 1 end
    local take = math.min(#text - sourceStart + 1, self.width - x + 1)
    if take <= 0 then return end
    local t = text:sub(sourceStart, sourceStart + take - 1)
    local f = fgStr:sub(sourceStart, sourceStart + take - 1)
    local b = bgStr:sub(sourceStart, sourceStart + take - 1)
    local row = self.rows[y]
    local left = x - 1
    local right = x + take
    row[1] = row[1]:sub(1,left) .. t .. row[1]:sub(right)
    row[2] = row[2]:sub(1,left) .. f .. row[2]:sub(right)
    row[3] = row[3]:sub(1,left) .. b .. row[3]:sub(right)
    self.dirty[y] = true
  end

  function self:write(x, y, text, fgColour, bgColour)
    text = tostring(text or "")
    self:blit(x, y, text,
      string.rep(h(fgColour or self.fg), #text),
      string.rep(h(bgColour or self.bg), #text))
  end

  function self:fill(x, y, w, ht, ch, fgColour, bgColour)
    ch = tostring(ch or " "):sub(1,1)
    local text = string.rep(ch, math.max(0, w))
    local fgLine = string.rep(h(fgColour or self.fg), #text)
    local bgLine = string.rep(h(bgColour or self.bg), #text)
    for yy = y, y + ht - 1 do self:blit(x, yy, text, fgLine, bgLine) end
  end

  function self:border(x, y, w, ht, fgColour, bgColour)
    if w < 2 or ht < 2 then return end
    self:write(x,y,"+"..string.rep("-",w-2).."+",fgColour,bgColour)
    for yy=y+1,y+ht-2 do self:write(x,yy,"|"..string.rep(" ",w-2).."|",fgColour,bgColour) end
    self:write(x,y+ht-1,"+"..string.rep("-",w-2).."+",fgColour,bgColour)
  end

  function self:getRow(y)
    local r = self.rows[y]
    if not r then return nil end
    return r[1], r[2], r[3]
  end

  function self:setRow(y, text, fgStr, bgStr)
    if y < 1 or y > self.height then return end
    if #text ~= self.width or #fgStr ~= self.width or #bgStr ~= self.width then
      error("row width mismatch", 2)
    end
    self.rows[y] = {text, fgStr, bgStr}
    self.dirty[y] = true
  end

  function self:markAllDirty()
    for y=1,self.height do self.dirty[y]=true end
  end

  function self:clean()
    self.dirty = {}
  end

  return self
end

M.toBlit = h
return M
