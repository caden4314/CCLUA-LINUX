local M = {}

function M.new(ctx)
  local self = {
    ctx = ctx,
    path = ctx.config.user.home,
    entries = {},
    selected = 1,
  }

  local function refresh()
    local list = ctx.vfs.list(self.path) or {}
    table.sort(list)
    self.entries = list
    if self.selected > #list then self.selected = math.max(1, #list) end
  end

  local function parent(path)
    local p = path:match("^(.*)/[^/]+$")
    if not p or p == "" then return "/" end
    return p
  end

  function self.draw(win)
    refresh()
    local s = win.surface
    s:clear(colors.black, colors.white)
    s:fill(1,1,s.width,2," ",colors.white,colors.gray)
    s:write(2,1,"Files",colors.white,colors.gray)
    s:write(2,2,self.path:sub(1,math.max(1,s.width-2)),colors.lightGray,colors.gray)
    local maxRows = s.height - 3
    for i=1,math.min(#self.entries,maxRows) do
      local name = self.entries[i]
      local full = ctx.vfs.normalize(self.path .. "/" .. name)
      local isDir = ctx.vfs.isDir(full)
      local active = i == self.selected
      local bg = active and colors.blue or colors.black
      local fg = isDir and colors.cyan or colors.white
      local prefix = isDir and "> " or "  "
      s:write(2,i+2,(prefix..name):sub(1,s.width-3),fg,bg)
    end
  end
  function self.event(event,a,b)
    if event == "key" then
      if a == keys.up then
        self.selected = math.max(1,self.selected-1)
      elseif a == keys.down then
        self.selected = math.min(math.max(1,#self.entries),self.selected+1)
      elseif a == keys.enter and self.entries[self.selected] then
        local target = ctx.vfs.normalize(self.path.."/"..self.entries[self.selected])
        if ctx.vfs.isDir(target) then self.path=target;self.selected=1 end
      elseif a == keys.backspace then
        self.path=parent(self.path);self.selected=1
      end
    end
    local win=ctx.compositor:getWindow(ctx.compositor.focused)
    if win and win.app==self then self.draw(win) end
  end

  refresh()
  return self
end

return M
