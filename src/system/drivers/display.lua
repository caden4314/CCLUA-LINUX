local M={}
local Font=ISO.require("system/ui/font6x9.lua")

local DEFAULT_PALETTE={
  [colors.white]={0.93,0.95,0.98},[colors.orange]={0.95,0.45,0.15},
  [colors.magenta]={0.78,0.32,0.86},[colors.lightBlue]={0.25,0.62,0.95},
  [colors.yellow]={0.98,0.78,0.18},[colors.lime]={0.30,0.80,0.34},
  [colors.pink]={0.95,0.40,0.62},[colors.gray]={0.16,0.18,0.22},
  [colors.lightGray]={0.48,0.52,0.60},[colors.cyan]={0.15,0.78,0.88},
  [colors.purple]={0.48,0.34,0.82},[colors.blue]={0.12,0.30,0.66},
  [colors.brown]={0.42,0.25,0.13},[colors.green]={0.10,0.48,0.28},
  [colors.red]={0.90,0.20,0.23},[colors.black]={0.025,0.032,0.045},
}

local HEX_INDEX={
  ["0"]=0,["1"]=1,["2"]=2,["3"]=3,["4"]=4,["5"]=5,["6"]=6,["7"]=7,
  ["8"]=8,["9"]=9,["a"]=10,["b"]=11,["c"]=12,["d"]=13,["e"]=14,["f"]=15,
}

local function pickTarget()
  local monitor=peripheral and peripheral.find and peripheral.find("monitor")
  if monitor then
    pcall(monitor.setTextScale,0.5)
    return monitor,"monitor"
  end
  return (term.native and term.native() or term.current()),"terminal"
end

local function readScale()
  local path="/.cclua/data/apps/settings/ui-scale"
  if not fs.exists(path) or fs.isDir(path) then return "1.0" end
  local h=fs.open(path,"r");if not h then return "1.0" end
  local raw=(h.readAll() or ""):gsub("%s+","");h.close()
  if raw=="0.5" or raw=="0.25" or raw=="1.0" then return raw end
  return "1.0"
end

local function colourIndex(ch)
  return HEX_INDEX[(ch or "f"):lower()] or 15
end

function M.open()
  local target,kind=pickTarget()
  local requestedScale=readScale()
  local graphicsCapable=type(target.setGraphicsMode)=="function" and type(target.drawPixels)=="function"
  local pixelMode=graphicsCapable and (requestedScale=="0.5" or requestedScale=="0.25")
  local cellW,cellH=6,9
  if requestedScale=="0.5" then cellW,cellH=3,5
  elseif requestedScale=="0.25" then cellW,cellH=2,3 end

  if pixelMode then
    local ok=pcall(target.setGraphicsMode,1)
    if not ok then pixelMode=false end
  else
    if graphicsCapable then pcall(target.setGraphicsMode,0) end
  end

  local self={
    target=target,kind=kind,palette={},frames=0,
    endpoint=pixelMode and "pixel16" or "text",
    requestedScale=requestedScale,cellWidth=cellW,cellHeight=cellH,
    graphicsCapable=graphicsCapable,
  }

  local function physicalSize()
    if self.endpoint=="pixel16" then
      local ok,w,h=pcall(target.getSize,true)
      if ok and tonumber(w) and tonumber(h) then return w,h end
      local tw,th=target.getSize()
      return tw*6,th*9
    end
    return target.getSize()
  end

  local function updateSize()
    local pw,ph=physicalSize()
    self.pixelWidth,self.pixelHeight=pw,ph
    if self.endpoint=="pixel16" then
      self.width=math.max(1,math.floor(pw/self.cellWidth))
      self.height=math.max(1,math.floor(ph/self.cellHeight))
    else
      self.width,self.height=pw,ph
      self.pixelWidth,self.pixelHeight=pw*6,ph*9
    end
  end

  updateSize()

  for colour,rgb in pairs(DEFAULT_PALETTE) do
    if target.setPaletteColor then pcall(target.setPaletteColor,colour,rgb[1],rgb[2],rgb[3]) end
    self.palette[colour]={rgb[1],rgb[2],rgb[3]}
  end

  if self.endpoint=="text" then
    target.setCursorBlink(false)
    target.setBackgroundColor(colors.black)
    target.clear()
  else
    target.drawPixels(0,0,colors.black,self.pixelWidth,self.pixelHeight)
  end

  function self:size()
    updateSize()
    return self.width,self.height
  end

  function self:pixelSize()
    updateSize()
    return self.pixelWidth,self.pixelHeight
  end

  function self:describe()
    return {
      endpoint=self.endpoint,kind=self.kind,scale=self.requestedScale,
      logicalWidth=self.width,logicalHeight=self.height,
      pixelWidth=self.pixelWidth,pixelHeight=self.pixelHeight,
      cellWidth=self.cellWidth,cellHeight=self.cellHeight,
      graphicsCapable=self.graphicsCapable,
    }
  end

  local function sampleGlyph(code,dx,dy)
    local glyph=Font[code] or Font[63] or {}
    local sx=math.min(5,math.floor((dx+0.5)*6/self.cellWidth))
    local sy=math.min(8,math.floor((dy+0.5)*9/self.cellHeight))
    local mask=glyph[sy+1] or 0
    return bit32.band(mask,bit32.lshift(1,5-sx))~=0
  end

  function self:blitLine(y,text,fg,bg)
    if y<1 or y>self.height then return end
    if self.endpoint=="text" then
      target.setCursorPos(1,y)
      target.blit(text,fg,bg)
      return
    end
    local maxChars=math.min(#text,self.width)
    local rows={}
    for dy=0,self.cellHeight-1 do
      local bytes={}
      for i=1,maxChars do
        local code=text:byte(i) or 32
        local f=colourIndex(fg:sub(i,i))
        local b=colourIndex(bg:sub(i,i))
        for dx=0,self.cellWidth-1 do
          bytes[#bytes+1]=string.char(sampleGlyph(code,dx,dy) and f or b)
        end
      end
      local remain=self.pixelWidth-(maxChars*self.cellWidth)
      if remain>0 then bytes[#bytes+1]=string.rep(string.char(15),remain) end
      rows[#rows+1]=table.concat(bytes)
    end
    target.drawPixels(0,(y-1)*self.cellHeight,rows,self.pixelWidth,self.cellHeight)
  end

  function self:mapInput(x,y)
    if self.endpoint~="pixel16" then return x,y end
    x=tonumber(x) or 0;y=tonumber(y) or 0
    return math.floor(x/self.cellWidth)+1,math.floor(y/self.cellHeight)+1
  end

  function self:setPalette(colour,r,g,b)
    if not target.setPaletteColor then return false end
    target.setPaletteColor(colour,r,g,b)
    self.palette[colour]={r,g,b}
    return true
  end

  function self:clear()
    if self.endpoint=="pixel16" then
      target.drawPixels(0,0,colors.black,self.pixelWidth,self.pixelHeight)
    else
      target.setBackgroundColor(colors.black)
      target.clear()
    end
  end

  function self:cursor(x,y,blink,colour)
    if self.endpoint=="pixel16" then return false end
    target.setCursorPos(x or 1,y or 1)
    if colour then target.setTextColor(colour) end
    target.setCursorBlink(not not blink)
    return true
  end

  function self:refreshSize()
    local ow,oh=self.width,self.height
    updateSize()
    return self.width~=ow or self.height~=oh,self.width,self.height
  end

  function self:isColor()
    return target.isColor and target.isColor() or false
  end

  return self
end

return M
