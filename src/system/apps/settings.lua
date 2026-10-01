local M={}

function M.new(ctx)
  local self={ctx=ctx,selected=1}
  local function palette()
    return ctx.theme and ctx.theme:palette() or ctx.config.theme or {}
  end
  local function themes()
    return ctx.theme and ctx.theme:list() or {}
  end

  function self.draw(win)
    local s=win.surface
    local p=palette()
    s:clear(p.background or colors.black,p.text or colors.white)
    s:fill(1,1,s.width,2," ",p.text or colors.white,p.panel or colors.gray)
    s:write(2,1,"Settings",p.accent or colors.cyan,p.panel or colors.gray)
    local current=ctx.theme and ctx.theme:status() or {name="Default"}
    s:write(2,2,"Appearance / "..current.name,p.muted or colors.lightGray,p.panel or colors.gray)

    s:write(2,4,"Appearance",p.accent or colors.cyan,p.background or colors.black)
    local list=themes()
    for i,item in ipairs(list) do
      local y=4+i
      if y<=s.height-6 then
        local active=item.id==(ctx.theme and ctx.theme:status().id)
        local selected=i==self.selected
        local bg=selected and (p.selection or colors.blue) or (p.background or colors.black)
        local mark=active and "* " or "  "
        s:write(3,y,(mark..item.name):sub(1,s.width-4),active and item.accent or (p.text or colors.white),bg)
      end
    end

    local y=math.max(9,#list+6)
    if y<=s.height-5 then
      s:write(2,y,"System",p.accent or colors.cyan,p.background or colors.black)
      s:write(3,y+1,ctx.config.name.." "..ctx.config.version,p.text or colors.white,p.background or colors.black)
      s:write(3,y+2,ctx.config.kernel,p.muted or colors.lightGray,p.background or colors.black)
      s:write(3,y+3,ctx.config.architecture.." / "..tostring(ctx.iso.meta.files or "?").." image files",p.muted or colors.lightGray,p.background or colors.black)
    end

    s:write(2,s.height,"Up/Down select  Enter apply",p.muted or colors.lightGray,p.background or colors.black)
  end

  local function applySelected()
    local list=themes()
    local item=list[self.selected]
    if item and ctx.theme then ctx.theme:set(item.id,true) end
  end

  function self.event(event,a,b)
    local list=themes()
    if event=="key" then
      if a==keys.up then self.selected=math.max(1,self.selected-1)
      elseif a==keys.down then self.selected=math.min(math.max(1,#list),self.selected+1)
      elseif a==keys.enter then applySelected() end
    elseif event=="mouse_click" then
      local _,_,y=a,b
      local idx=y-4
      if idx>=1 and idx<=#list then self.selected=idx;applySelected() end
    elseif event=="cclua_theme_changed" then
      for i,item in ipairs(list) do
        if item.id==(ctx.theme and ctx.theme:status().id) then self.selected=i;break end
      end
    end
    local win=ctx.compositor:getWindow(ctx.compositor.focused)
    if win and win.app==self then self.draw(win) end
  end

  local current=ctx.theme and ctx.theme:status().id
  for i,item in ipairs(themes()) do if item.id==current then self.selected=i;break end end
  return self
end

return M
