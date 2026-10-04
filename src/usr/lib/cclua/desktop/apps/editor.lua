local M={}

local function host(path)
  local p=tostring(path or ""):gsub("^/","")
  return p=="" and "/" or p
end

local function split_lines(text)
  local out={}
  text=tostring(text or ""):gsub("\r\n","\n"):gsub("\r","\n")
  if text=="" then return {""} end
  for line in (text.."\n"):gmatch("(.-)\n") do out[#out+1]=line end
  if #out>1 and out[#out]=="" then table.remove(out,#out) end
  if #out==0 then out={""} end
  return out
end

local function load_file(path)
  local p=host(path)
  if not fs.exists(p) then return {""},nil end
  if fs.isDir(p) then return nil,"is a directory" end
  local size=fs.getSize(p)
  if size>65536 then return nil,"file is larger than 64 KiB" end
  local h,err=fs.open(p,"r")
  if not h then return nil,err or "open failed" end
  local data=h.readAll()
  h.close()
  return split_lines(data)
end

local function save_file(st)
  local p=host(st.path)
  local dir=fs.getDir(p)
  if dir~="" and not fs.exists(dir) then fs.makeDir(dir) end
  local h,err=fs.open(p,"w")
  if not h then st.message=err or "save failed";return false end
  h.write(table.concat(st.lines,"\n"))
  h.close()
  st.dirty=false
  st.message="Saved"
  return true
end

local function clamp(st)
  st.row=math.max(1,math.min(#st.lines,st.row))
  local line=st.lines[st.row] or ""
  st.col=math.max(1,math.min(#line+1,st.col))
end

local function ensure_visible(st,rows)
  if st.row<st.scroll then st.scroll=st.row end
  if st.row>=st.scroll+rows then st.scroll=st.row-rows+1 end
  st.scroll=math.max(1,st.scroll)
end

local function open_path(st,path)
  path=path or "/home/caden/untitled.txt"
  local lines,err=load_file(path)
  if not lines then
    st.message=tostring(err)
    return false
  end
  st.path=path
  st.lines=lines
  st.row=1
  st.col=1
  st.scroll=1
  st.dirty=false
  st.message=nil
  return true
end

function M.new(ctx,opts)
  local st={
    title="Text Editor",icon="E",
    path="/home/caden/untitled.txt",
    lines={""},row=1,col=1,scroll=1,
    dirty=false,message=nil,ctrl=false,
  }
  open_path(st,opts and opts.path or st.path)
  return st
end

function M.open(ctx,st,opts)
  if opts and opts.path then return open_path(st,opts.path) end
  return false
end

function M.snapshot(st)
  return {path=st.path}
end

function M.draw(ctx,st,ui,x,y,w,h,active)
  ui.fill(x,y,x+w-1,y+h-1,colors.black,colors.white)
  local hp=host(st.path)
  local name=hp:match("([^/]+)$") or hp:match("([^\\]+)$") or hp
  local title=(st.dirty and "* " or "")..name.."  —  Text Editor"
  ui.fill(x,y,x+w-1,y,colors.gray,colors.white)
  ui.text(x+1,y,title:sub(1,math.max(1,w-2)),colors.white,colors.gray)

  local contentY=y+1
  local footerY=y+h-1
  local rows=math.max(1,h-2)
  ensure_visible(st,rows)

  local gutter=(w>=28) and 4 or 0
  for screenRow=1,rows do
    local idx=st.scroll+screenRow-1
    local yy=contentY+screenRow-1
    ui.fill(x,yy,x+w-1,yy,colors.black,colors.white)
    if idx<=#st.lines then
      if gutter>0 then
        local ln=("%3d "):format(idx)
        ui.text(x,yy,ln,colors.gray,colors.black)
      end
      local line=st.lines[idx] or ""
      local avail=w-gutter
      ui.text(x+gutter,yy,line:sub(1,avail),colors.lightGray,colors.black)
    end
  end

  ui.fill(x,footerY,x+w-1,footerY,colors.gray,colors.white)
  local status=("Ln %d, Col %d"):format(st.row,st.col)
  ui.text(x+1,footerY,status,colors.white,colors.gray)
  local right=st.message or "Ctrl+S save"
  if #right>w-#status-4 then right=right:sub(1,math.max(1,w-#status-4)) end
  ui.text(math.max(x+1,x+w-#right-1),footerY,right,st.message and colors.orange or colors.lightGray,colors.gray)

  if active then
    local visibleRow=st.row-st.scroll
    if visibleRow>=0 and visibleRow<rows then
      ui.cursor=x+gutter+math.min(math.max(0,st.col-1),math.max(0,w-gutter-1))
      ui.cursor_y=contentY+visibleRow
    end
  end
end

local function insert_char(st,ch)
  local line=st.lines[st.row] or ""
  st.lines[st.row]=line:sub(1,st.col-1)..ch..line:sub(st.col)
  st.col=st.col+#ch
  st.dirty=true
  st.message=nil
end

function M.event(ctx,st,ev,a,b,c,rx,ry,w,h)
  if ev=="char" then
    insert_char(st,tostring(a))
    return true
  end

  if ev=="key_up" then
    if a==keys.leftCtrl or a==keys.rightCtrl then st.ctrl=false end
    return false
  end

  if ev=="key" then
    if a==keys.leftCtrl or a==keys.rightCtrl then st.ctrl=true;return true end
    if st.ctrl and a==keys.s then save_file(st);return true end

    if a==keys.left then st.col=st.col-1
    elseif a==keys.right then st.col=st.col+1
    elseif a==keys.up then st.row=st.row-1
    elseif a==keys.down then st.row=st.row+1
    elseif a==keys.home then st.col=1
    elseif a==keys["end"] then st.col=#(st.lines[st.row] or "")+1
    elseif a==keys.backspace then
      if st.col>1 then
        local line=st.lines[st.row]
        st.lines[st.row]=line:sub(1,st.col-2)..line:sub(st.col)
        st.col=st.col-1
        st.dirty=true
      elseif st.row>1 then
        local prev=st.lines[st.row-1]
        local line=table.remove(st.lines,st.row)
        st.row=st.row-1
        st.col=#prev+1
        st.lines[st.row]=prev..line
        st.dirty=true
      end
    elseif a==keys.delete then
      local line=st.lines[st.row]
      if st.col<=#line then
        st.lines[st.row]=line:sub(1,st.col-1)..line:sub(st.col+1)
        st.dirty=true
      elseif st.row<#st.lines then
        st.lines[st.row]=line..table.remove(st.lines,st.row+1)
        st.dirty=true
      end
    elseif a==keys.enter then
      local line=st.lines[st.row]
      local before=line:sub(1,st.col-1)
      local after=line:sub(st.col)
      st.lines[st.row]=before
      table.insert(st.lines,st.row+1,after)
      st.row=st.row+1
      st.col=1
      st.dirty=true
    elseif a==keys.f2 then
      save_file(st)
    else
      return false
    end
    clamp(st)
    return true
  end

  if ev=="mouse_click" and ry and ry>=2 and ry<=h-1 then
    local gutter=(w>=28) and 4 or 0
    local row=st.scroll+ry-2
    if row>=1 and row<=#st.lines then
      st.row=row
      st.col=math.max(1,math.min(#st.lines[row]+1,(rx or 1)-gutter))
      clamp(st)
      return true
    end
  end

  if ev=="mouse_scroll" then
    st.scroll=math.max(1,st.scroll+(tonumber(a) or 0))
    return true
  end
  return false
end

return M
