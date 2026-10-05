local M={}

local function blit_color(c)
  if colors and colors.toBlit then return colors.toBlit(c) end
  local n,v=0,tonumber(c) or 1
  while v>1 do v=v/2;n=n+1 end
  return ("%x"):format(n)
end

local function blank_row(cols,fg,bg)
  return {
    ch=string.rep(" ",cols),
    fg=string.rep(blit_color(fg),cols),
    bg=string.rep(blit_color(bg),cols),
  }
end

local function new_screen(cols,rows,fg,bg)
  local out={}
  for y=1,rows do out[y]=blank_row(cols,fg,bg) end
  return out
end

local function patch(s,x,text)
  if x<1 then text=text:sub(2-x);x=1 end
  if x>#s or text=="" then return s end
  if x+#text-1>#s then text=text:sub(1,#s-x+1) end
  return s:sub(1,x-1)..text..s:sub(x+#text)
end

local function resize_row(row,cols,fg,bg)
  local function fit(s,pad)
    s=tostring(s or "")
    if #s>cols then return s:sub(1,cols) end
    if #s<cols then return s..string.rep(pad,cols-#s) end
    return s
  end
  return {
    ch=fit(row and row.ch," "),
    fg=fit(row and row.fg,blit_color(fg)),
    bg=fit(row and row.bg,blit_color(bg)),
  }
end

function M.new(cols,rows,opts)
  opts=opts or {}
  cols=math.max(1,math.floor(tonumber(cols) or 51))
  rows=math.max(1,math.floor(tonumber(rows) or 19))
  local fg=(colors and colors.white) or 1
  local bg=(colors and colors.black) or 32768
  local p={
    id=opts.id,cols=cols,rows=rows,fg=fg,bg=bg,
    cursor_x=1,cursor_y=1,cursor_blink=false,
    main=new_screen(cols,rows,fg,bg),alt=nil,use_alt=false,
    main_cursor=nil,closed=false,foreground_pgid=nil,
    input={},events={},scrollback={},palette={},revision=0,
    dirty=true,notify_pending=false,notify=opts.notify,
  }

  local function active()
    return p.use_alt and p.alt or p.main
  end

  function p:_touch()
    self.revision=self.revision+1
    self.dirty=true
    if self.notify and not self.notify_pending then
      self.notify_pending=true
      pcall(self.notify,self)
    end
  end

  function p:ack()
    self.dirty=false
    self.notify_pending=false
  end
  function p:set_notify(fn)
    self.notify=fn
  end

  function p:push_input(x)
    self.input[#self.input+1]=tostring(x or "")
  end

  function p:read_input()
    if #self.input==0 then return nil end
    return table.remove(self.input,1)
  end

  function p:push_event(ev)
    if type(ev)~="table" then return nil,"EINVAL" end
    self.events[#self.events+1]=ev
    return true
  end

  function p:pop_event()
    if #self.events==0 then return nil end
    return table.remove(self.events,1)
  end

  function p:take_scrollback()
    local out=self.scrollback
    self.scrollback={}
    return out
  end

  function p:snapshot()
    return {
      cols=self.cols,rows=self.rows,cursor_x=self.cursor_x,cursor_y=self.cursor_y,
      cursor_blink=self.cursor_blink,fg=self.fg,bg=self.bg,
      alternate=self.use_alt,screen=active(),revision=self.revision,
    }
  end

  function p:scroll(n)
    n=math.floor(tonumber(n) or 0)
    if n==0 then return end
    local scr=active()
    if n>0 then
      for _=1,math.min(n,self.rows) do
        local gone=table.remove(scr,1)
        if not self.use_alt and gone then self.scrollback[#self.scrollback+1]=gone end
        scr[#scr+1]=blank_row(self.cols,self.fg,self.bg)
      end
    else
      for _=1,math.min(-n,self.rows) do
        table.remove(scr,#scr)
        table.insert(scr,1,blank_row(self.cols,self.fg,self.bg))
      end
    end
    self:_touch()
  end

  local function newline()
    p.cursor_x=1
    if p.cursor_y>=p.rows then p:scroll(1) else p.cursor_y=p.cursor_y+1 end
  end

  function p:_write(text,fgs,bgs)
    if self.closed then return nil,"EIO" end
    text=tostring(text or "")
    local pos=1
    while pos<=#text do
      local nl=text:find("\n",pos,true)
      local part=nl and text:sub(pos,nl-1) or text:sub(pos)
      if part~="" then
        local scr=active()
        local row=scr[self.cursor_y]
        local max=math.max(0,self.cols-self.cursor_x+1)
        local shown=part:sub(1,max)
        row.ch=patch(row.ch,self.cursor_x,shown)
        if fgs then row.fg=patch(row.fg,self.cursor_x,fgs:sub(1,#shown))
        else row.fg=patch(row.fg,self.cursor_x,string.rep(blit_color(self.fg),#shown)) end
        if bgs then row.bg=patch(row.bg,self.cursor_x,bgs:sub(1,#shown))
        else row.bg=patch(row.bg,self.cursor_x,string.rep(blit_color(self.bg),#shown)) end
        self.cursor_x=math.min(self.cols+1,self.cursor_x+#shown)
      end
      if not nl then break end
      newline()
      pos=nl+1
    end
    self:_touch()
    return true
  end

  function p:resize(newCols,newRows)
    newCols=math.max(1,math.floor(tonumber(newCols) or self.cols))
    newRows=math.max(1,math.floor(tonumber(newRows) or self.rows))
    if newCols==self.cols and newRows==self.rows then return false end

    local function resize_screen(scr,isMain)
      if not scr then return nil end
      if #scr>newRows then
        local remove=#scr-newRows
        for _=1,remove do
          local gone=table.remove(scr,1)
          if isMain and gone then self.scrollback[#self.scrollback+1]=gone end
        end
      end
      while #scr<newRows do scr[#scr+1]=blank_row(newCols,self.fg,self.bg) end
      for y=1,#scr do scr[y]=resize_row(scr[y],newCols,self.fg,self.bg) end
      return scr
    end

    self.main=resize_screen(self.main,true)
    self.alt=resize_screen(self.alt,false)
    self.cols,self.rows=newCols,newRows
    self.cursor_x=math.max(1,math.min(newCols+1,self.cursor_x))
    self.cursor_y=math.max(1,math.min(newRows,self.cursor_y))
    self:_touch()
    return true
  end

  function p:set_alternate_screen(enabled)
    enabled=enabled==true
    if enabled==self.use_alt then return false end
    if enabled then
      self.main_cursor={self.cursor_x,self.cursor_y,self.cursor_blink}
      self.alt=new_screen(self.cols,self.rows,self.fg,self.bg)
      self.cursor_x,self.cursor_y,self.cursor_blink=1,1,false
      self.use_alt=true
    else
      self.use_alt=false
      local c=self.main_cursor or {1,1,false}
      self.cursor_x,self.cursor_y,self.cursor_blink=c[1],c[2],c[3]
      self.alt=nil
      self.main_cursor=nil
    end
    self:_touch()
    return true
  end

  function p:write_stream(kind,text)
    if kind=="stderr" then
      local old=self.fg
      if colors then self.fg=colors.red end
      local ok,err=self:_write(text)
      self.fg=old
      return ok,err
    end
    return self:_write(text)
  end
  function p:close()
    self.closed=true
    self:_touch()
  end

  local t={}
  function t.write(s) return p:_write(s) end
  function t.blit(s,fgs,bgs)
    s=tostring(s or "")
    fgs=tostring(fgs or "")
    bgs=tostring(bgs or "")
    if #s~=#fgs or #s~=#bgs then error("Arguments must be the same length",2) end
    return p:_write(s,fgs,bgs)
  end
  function t.clear()
    if p.use_alt then p.alt=new_screen(p.cols,p.rows,p.fg,p.bg)
    else p.main=new_screen(p.cols,p.rows,p.fg,p.bg) end
    p:_touch()
  end
  function t.clearLine()
    active()[p.cursor_y]=blank_row(p.cols,p.fg,p.bg)
    p:_touch()
  end
  function t.getCursorPos() return p.cursor_x,p.cursor_y end
  function t.setCursorPos(x,y)
    p.cursor_x=math.max(1,math.min(p.cols+1,math.floor(tonumber(x) or 1)))
    p.cursor_y=math.max(1,math.min(p.rows,math.floor(tonumber(y) or 1)))
    p:_touch()
  end
  function t.setCursorBlink(v) p.cursor_blink=v==true;p:_touch() end
  function t.getCursorBlink() return p.cursor_blink end
  function t.getSize() return p.cols,p.rows end
  function t.scroll(n) return p:scroll(n) end
  function t.isColor() return true end
  t.isColour=t.isColor
  function t.setTextColor(c) p.fg=c;p:_touch() end
  t.setTextColour=t.setTextColor
  function t.getTextColor() return p.fg end
  t.getTextColour=t.getTextColor
  function t.setBackgroundColor(c) p.bg=c;p:_touch() end
  t.setBackgroundColour=t.setBackgroundColor
  function t.getBackgroundColor() return p.bg end
  t.getBackgroundColour=t.getBackgroundColor
  function t.setPaletteColor(c,a,b,d)
    p.palette[c]={a,b,d}
    p:_touch()
  end
  t.setPaletteColour=t.setPaletteColor
  function t.getPaletteColor(c)
    local v=p.palette[c]
    if v then return v[1],v[2],v[3] end
    if term and term.nativePaletteColor then return term.nativePaletteColor(c) end
    return 1,1,1
  end
  t.getPaletteColour=t.getPaletteColor

  p.term=t
  p.stdin={read=function() return p:read_input() end}
  p.stdout={write=function(s) return p:write_stream("stdout",s) end}
  p.stderr={write=function(s) return p:write_stream("stderr",s) end}
  return p
end

return M
