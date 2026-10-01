local M = {}

function M.new(ctx)
  local self = {ctx=ctx,path=ctx.config.user.home,entries={},selected=1}

  local function palette()
    return ctx.theme and ctx.theme:palette() or ctx.config.theme or {}
  end

  local function refresh()
    local list = ctx.vfs.list(self.path) or {}
    table.sort(list,function(a,b)
      local ad=ctx.vfs.isDir(ctx.vfs.normalize(self.path.."/"..a))
      local bd=ctx.vfs.isDir(ctx.vfs.normalize(self.path.."/"..b))
      if ad~=bd then return ad end
      return a:lower()<b:lower()
    end)
    self.entries=list
    if self.selected>#list then self.selected=math.max(1,#list) end
  end

  local function parent(path)
    local p=path:match("^(.*)/[^/]+$")
    if not p or p=="" then return "/" end
    return p
  end

  local function openSelected()
    local name=self.entries[self.selected]
    if not name then return end
    local target=ctx.vfs.normalize(self.path.."/"..name)
    if ctx.vfs.isDir(target) then self.path=target;self.selected=1 end
  end

  function self.draw(win)
    refresh()
    local p=palette()
    local s=win.surface
    s:clear(p.background or colors.black,p.text or colors.white)
    s:fill(1,1,s.width,2," ",p.text or colors.white,p.panel or colors.gray)
    s:write(2,1,"Files",p.accent or colors.cyan,p.panel or colors.gray)
    s:write(2,2,self.path:sub(1,math.max(1,s.width-2)),p.muted or colors.lightGray,p.panel or colors.gray)

    local maxRows=s.height-4
    for i=1,math.min(#self.entries,maxRows) do
      local name=self.entries[i]
      local full=ctx.vfs.normalize(self.path.."/"..name)
      local isDir=ctx.vfs.isDir(full)
      local active=i==self.selected
      local bg=active and (p.selection or colors.blue) or (p.background or colors.black)
      local fg=isDir and (p.accent or colors.cyan) or (p.text or colors.white)
      local prefix=isDir and "[D] " or "    "
      s:write(2,i+2,(prefix..name):sub(1,s.width-3),fg,bg)
    end
    if #self.entries==0 then s:write(3,4,"This folder is empty",p.muted or colors.lightGray,p.background or colors.black) end
    local info=tostring(#self.entries).." item"..(#self.entries==1 and "" or "s").."   Enter open   Backspace up"
    s:write(2,s.height,info:sub(1,s.width-1),p.muted or colors.lightGray,p.background or colors.black)
  end

  function self.event(event,a,b,c)
    if event=="key" then
      if a==keys.up then self.selected=math.max(1,self.selected-1)
      elseif a==keys.down then self.selected=math.min(math.max(1,#self.entries),self.selected+1)
      elseif a==keys.enter then openSelected()
      elseif a==keys.backspace then self.path=parent(self.path);self.selected=1 end
    elseif event=="mouse_click" then
      local y=c
      local idx=(tonumber(y) or 0)-2
      if idx>=1 and idx<=#self.entries then
        if self.selected==idx then openSelected() else self.selected=idx end
      end
    end
    local win=ctx.compositor:getWindow(ctx.compositor.focused)
    if win and win.app==self then self.draw(win) end
  end

  refresh()
  return self
end

return M
