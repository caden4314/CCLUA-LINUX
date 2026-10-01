local M={}
local SCALE_PATH="/AppData/settings/ui-scale"
local SCALES={"1.0","0.5"}

function M.new(ctx)
  local self={ctx=ctx,cursor=1,status=nil}

  local function palette()
    return ctx.theme and ctx.theme:palette() or ctx.config.theme or {}
  end

  local function themes()
    return ctx.theme and ctx.theme:list() or {}
  end

  local function readScale()
    local value=ctx.vfs.read(SCALE_PATH)
    value=type(value)=="string" and value:gsub("%s+","") or nil
    if value=="1.0" or value=="0.5" then return value end
    return "0.5"
  end

  local function saveScale(value)
    local ok,err=ctx.vfs.mkdir("/AppData/settings")
    if not ok and not ctx.vfs.exists("/AppData/settings") then
      self.status="Scale save failed: "..tostring(err)
      return
    end
    local wrote,werr=ctx.vfs.write(SCALE_PATH,value,false)
    if not wrote then
      self.status="Scale save failed: "..tostring(werr)
      return
    end
    self.status="UI scale "..value.." saved - relaunch CCLUA to apply"
    os.queueEvent("cclua_ui_scale_changed",value)
  end

  local function totalRows()
    return #themes()+#SCALES
  end

  local function applyCursor()
    local list=themes()
    if self.cursor<=#list then
      local item=list[self.cursor]
      if item and ctx.theme then ctx.theme:set(item.id,true) end
    else
      local value=SCALES[self.cursor-#list]
      if value then saveScale(value) end
    end
  end

  function self.draw(win)
    local s=win.surface
    local p=palette()
    local list=themes()
    s:clear(p.background or colors.black,p.text or colors.white)
    s:fill(1,1,s.width,2," ",p.text or colors.white,p.panel or colors.gray)
    s:write(2,1,"Settings",p.accent or colors.cyan,p.panel or colors.gray)
    local current=ctx.theme and ctx.theme:status() or {name="Default"}
    s:write(2,2,("Appearance / "..current.name):sub(1,s.width-2),p.muted or colors.lightGray,p.panel or colors.gray)

    s:write(2,4,"Theme",p.accent or colors.cyan,p.background or colors.black)
    for i,item in ipairs(list) do
      local y=4+i
      local active=item.id==(ctx.theme and ctx.theme:status().id)
      local selected=self.cursor==i
      local bg=selected and (p.selection or colors.blue) or (p.background or colors.black)
      local mark=active and "* " or "  "
      s:write(3,y,(mark..item.name):sub(1,s.width-4),active and item.accent or (p.text or colors.white),bg)
    end

    local sy=9
    s:write(2,sy,"UI Scale",p.accent or colors.cyan,p.background or colors.black)
    local currentScale=readScale()
    for i,value in ipairs(SCALES) do
      local y=sy+i
      local active=value==currentScale
      local selected=self.cursor==#list+i
      local bg=selected and (p.selection or colors.blue) or (p.background or colors.black)
      local mark=active and "* " or "  "
      local label=value=="0.5" and "0.5  Compact / high density" or "1.0  Standard"
      s:write(3,y,(mark..label):sub(1,s.width-4),p.text or colors.white,bg)
    end

    local y=13
    if y<=s.height-4 then
      s:write(2,y,"System",p.accent or colors.cyan,p.background or colors.black)
      s:write(3,y+1,(ctx.config.name.." "..ctx.config.version):sub(1,s.width-4),p.text or colors.white,p.background or colors.black)
      s:write(3,y+2,ctx.config.kernel:sub(1,s.width-4),p.muted or colors.lightGray,p.background or colors.black)
    end

    if self.status and s.height>=17 then
      s:write(2,s.height-1,self.status:sub(1,s.width-2),p.muted or colors.lightGray,p.background or colors.black)
    end
    s:write(2,s.height,"Mouse or Up/Down + Enter",p.muted or colors.lightGray,p.background or colors.black)
  end

  function self.event(event,a,b,c)
    local list=themes()
    if event=="key" then
      if a==keys.up then self.cursor=math.max(1,self.cursor-1)
      elseif a==keys.down then self.cursor=math.min(totalRows(),self.cursor+1)
      elseif a==keys.enter then applyCursor() end
    elseif event=="mouse_click" then
      local y=tonumber(c) or 0
      local themeIdx=y-4
      if themeIdx>=1 and themeIdx<=#list then
        self.cursor=themeIdx
        applyCursor()
      else
        local scaleIdx=y-9
        if scaleIdx>=1 and scaleIdx<=#SCALES then
          self.cursor=#list+scaleIdx
          applyCursor()
        end
      end
    elseif event=="cclua_theme_changed" then
      -- Redraw below picks up the new palette.
    end
    local win=ctx.compositor:getWindow(ctx.compositor.focused)
    if win and win.app==self then self.draw(win) end
  end

  local current=ctx.theme and ctx.theme:status().id
  for i,item in ipairs(themes()) do
    if item.id==current then self.cursor=i;break end
  end
  return self
end

return M
