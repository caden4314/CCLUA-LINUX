local M={}
local Theme=dofile("/usr/lib/cclua/desktop/theme.lua")

local DEFAULT_PATH="/home/caden/untitled.txt"
local MAX_BYTES=256*1024
local TAB="    "

local function host(path)
  local p=tostring(path or ""):gsub("^/","")
  return p=="" and "/" or p
end

local function basename(path)
  path=tostring(path or "")
  return path:match("([^/]+)$") or path:match("([^\\]+)$") or path
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

local function clone_lines(lines)
  local out={}
  for i,line in ipairs(lines or {}) do out[i]=line end
  return out
end

local function load_file(path)
  local p=host(path)
  if not fs.exists(p) then return {""},nil end
  if fs.isDir(p) then return nil,"is a directory" end
  local size=fs.getSize(p)
  if size>MAX_BYTES then return nil,"file is larger than 256 KiB" end
  local h,err=fs.open(p,"r")
  if not h then return nil,err or "open failed" end
  local data=h.readAll() or ""
  h.close()
  return split_lines(data)
end

local function save_file(st,path)
  path=path or st.path
  local p=host(path)
  local dir=fs.getDir(p)
  if dir~="" and not fs.exists(dir) then fs.makeDir(dir) end

  local data=table.concat(st.lines,"\n")
  if #data>MAX_BYTES then
    st.message="File exceeds 256 KiB editor limit"
    st.messageTone="danger"
    return false
  end

  local h,err=fs.open(p,"w")
  if not h then
    st.message=err or "save failed"
    st.messageTone="danger"
    return false
  end
  h.write(data)
  h.close()

  st.path=path
  st.dirty=false
  st.message="Saved "..basename(path)
  st.messageTone="success"
  st.confirmDiscard=false
  return true
end

local function clamp(st)
  st.row=math.max(1,math.min(#st.lines,tonumber(st.row) or 1))
  local line=st.lines[st.row] or ""
  st.col=math.max(1,math.min(#line+1,tonumber(st.col) or 1))
end
local function pos(row,col)
  return {row=row,col=col}
end

local function pos_before(a,b)
  return a.row<b.row or (a.row==b.row and a.col<b.col)
end

local function has_selection(st)
  local a,b=st.selAnchor,st.selCursor
  return a and b and (a.row~=b.row or a.col~=b.col)
end

local function ordered_selection(st)
  if not has_selection(st) then return nil,nil end
  if pos_before(st.selAnchor,st.selCursor) then return st.selAnchor,st.selCursor end
  return st.selCursor,st.selAnchor
end

local function clear_selection(st)
  st.selAnchor=nil
  st.selCursor=nil
  st.mouseSelecting=false
end

local function selected_text(st)
  local first,last=ordered_selection(st)
  if not first then return "" end
  if first.row==last.row then
    return (st.lines[first.row] or ""):sub(first.col,last.col-1)
  end
  local parts={(st.lines[first.row] or ""):sub(first.col)}
  for row=first.row+1,last.row-1 do parts[#parts+1]=st.lines[row] or "" end
  parts[#parts+1]=(st.lines[last.row] or ""):sub(1,last.col-1)
  return table.concat(parts,"\n")
end

local function document_snapshot(st)
  return {
    lines=clone_lines(st.lines),row=st.row,col=st.col,
    scroll=st.scroll,scrollX=st.scrollX,dirty=st.dirty,
  }
end

local function restore_snapshot(st,snap)
  st.lines=clone_lines(snap.lines)
  st.row=snap.row;st.col=snap.col
  st.scroll=snap.scroll or 1
  st.scrollX=snap.scrollX or 0
  st.dirty=snap.dirty==true
  clear_selection(st)
  clamp(st)
end

local function push_undo(st)
  st.undo[#st.undo+1]=document_snapshot(st)
  while #st.undo>32 do table.remove(st.undo,1) end
  st.redo={}
end

local function undo(st)
  local snap=table.remove(st.undo)
  if not snap then st.message="Nothing to undo";st.messageTone="muted";return false end
  st.redo[#st.redo+1]=document_snapshot(st)
  restore_snapshot(st,snap)
  st.message="Undo";st.messageTone="muted"
  return true
end

local function redo(st)
  local snap=table.remove(st.redo)
  if not snap then st.message="Nothing to redo";st.messageTone="muted";return false end
  st.undo[#st.undo+1]=document_snapshot(st)
  restore_snapshot(st,snap)
  st.message="Redo";st.messageTone="muted"
  return true
end

local function delete_selection(st,noUndo)
  local first,last=ordered_selection(st)
  if not first then return false end
  if not noUndo then push_undo(st) end

  if first.row==last.row then
    local line=st.lines[first.row] or ""
    st.lines[first.row]=line:sub(1,first.col-1)..line:sub(last.col)
  else
    local head=(st.lines[first.row] or ""):sub(1,first.col-1)
    local tail=(st.lines[last.row] or ""):sub(last.col)
    for row=last.row,first.row+1,-1 do table.remove(st.lines,row) end
    st.lines[first.row]=head..tail
  end

  st.row=first.row
  st.col=first.col
  st.dirty=true
  clear_selection(st)
  clamp(st)
  return true
end
local function insert_text(st,text)
  text=tostring(text or ""):gsub("\r\n","\n"):gsub("\r","\n")
  if text=="" then return end
  push_undo(st)
  if has_selection(st) then delete_selection(st,true) end

  local line=st.lines[st.row] or ""
  local before=line:sub(1,st.col-1)
  local after=line:sub(st.col)
  local parts=split_lines(text)

  if #parts==1 and not text:find("\n",1,true) then
    st.lines[st.row]=before..text..after
    st.col=st.col+#text
  else
    local raw={}
    local start=1
    while true do
      local p=text:find("\n",start,true)
      if not p then
        raw[#raw+1]=text:sub(start)
        break
      end
      raw[#raw+1]=text:sub(start,p-1)
      start=p+1
    end
    if #raw==0 then raw={""} end

    st.lines[st.row]=before..raw[1]
    local insertAt=st.row+1
    for i=2,#raw do
      table.insert(st.lines,insertAt,raw[i])
      insertAt=insertAt+1
    end
    st.row=st.row+#raw-1
    st.col=#raw[#raw]+1
    st.lines[st.row]=(st.lines[st.row] or "")..after
  end

  st.dirty=true
  st.message=nil
  st.messageTone=nil
  st.confirmDiscard=false
  clamp(st)
end

local function backspace(st)
  if has_selection(st) then push_undo(st);return delete_selection(st,true) end
  if st.col<=1 and st.row<=1 then return false end
  push_undo(st)

  if st.col>1 then
    local line=st.lines[st.row] or ""
    st.lines[st.row]=line:sub(1,st.col-2)..line:sub(st.col)
    st.col=st.col-1
  else
    local prev=st.lines[st.row-1] or ""
    local line=table.remove(st.lines,st.row) or ""
    st.row=st.row-1
    st.col=#prev+1
    st.lines[st.row]=prev..line
  end
  st.dirty=true
  return true
end

local function delete_forward(st)
  if has_selection(st) then push_undo(st);return delete_selection(st,true) end
  local line=st.lines[st.row] or ""
  if st.col>#line and st.row>=#st.lines then return false end
  push_undo(st)

  if st.col<=#line then
    st.lines[st.row]=line:sub(1,st.col-1)..line:sub(st.col+1)
  else
    st.lines[st.row]=line..table.remove(st.lines,st.row+1)
  end
  st.dirty=true
  return true
end

local function open_path(st,path,force)
  path=path or DEFAULT_PATH
  if not force and st.dirty and path~=st.path then
    st.pendingOpen=path
    st.mode="confirm-open"
    st.message="Unsaved changes: Y open anyway / N cancel"
    st.messageTone="warning"
    return false
  end

  local lines,err=load_file(path)
  if not lines then
    st.message=tostring(err)
    st.messageTone="danger"
    return false
  end

  st.path=path
  st.lines=lines
  st.row=1;st.col=1
  st.scroll=1;st.scrollX=0
  st.dirty=false
  st.message=nil;st.messageTone=nil
  st.mode=nil;st.modeInput=""
  st.pendingOpen=nil
  st.undo={};st.redo={}
  clear_selection(st)
  return true
end

local function move_cursor(st,row,col,extend)
  local old=pos(st.row,st.col)
  if extend and not st.selAnchor then st.selAnchor=old end
  st.row=row;st.col=col
  clamp(st)
  if extend then
    st.selCursor=pos(st.row,st.col)
  else
    clear_selection(st)
  end
end
local function word_left(line,col)
  local i=math.max(1,col-1)
  while i>1 and line:sub(i-1,i-1):match("%s") do i=i-1 end
  while i>1 and line:sub(i-1,i-1):match("[%w_]") do i=i-1 end
  return i
end

local function word_right(line,col)
  local i=math.max(1,col)
  while i<=#line and line:sub(i,i):match("[%w_]") do i=i+1 end
  while i<=#line and line:sub(i,i):match("%s") do i=i+1 end
  return i
end

local function ensure_visible(st,rows,cols)
  if st.row<st.scroll then st.scroll=st.row end
  if st.row>=st.scroll+rows then st.scroll=st.row-rows+1 end
  st.scroll=math.max(1,st.scroll)

  local zeroCol=math.max(0,st.col-1)
  if zeroCol<st.scrollX then st.scrollX=zeroCol end
  if zeroCol>=st.scrollX+cols then st.scrollX=zeroCol-cols+1 end
  st.scrollX=math.max(0,st.scrollX)
end

local function find_next(st,query,fromStart)
  query=tostring(query or "")
  if query=="" then return false end
  local needle=query:lower()
  local startRow=fromStart and 1 or st.row
  local startCol=fromStart and 1 or math.min(#(st.lines[st.row] or "")+1,st.col+1)

  local function scan(a,b,firstCol)
    for row=a,b do
      local line=(st.lines[row] or "")
      local at=line:lower():find(needle,row==a and firstCol or 1,true)
      if at then
        st.row=row
        st.col=at+#query
        st.selAnchor=pos(row,at)
        st.selCursor=pos(row,at+#query)
        st.findTerm=query
        st.message=("Found at %d:%d"):format(row,at)
        st.messageTone="success"
        return true
      end
    end
  end

  if scan(startRow,#st.lines,startCol) then return true end
  if startRow>1 and scan(1,startRow,1) then return true end
  st.message="No match for "..query
  st.messageTone="warning"
  return false
end

local function goto_line(st,value)
  local line=tonumber(value)
  if not line then
    st.message="Invalid line number"
    st.messageTone="danger"
    return false
  end
  st.row=math.max(1,math.min(#st.lines,math.floor(line)))
  st.col=math.min(st.col,#(st.lines[st.row] or "")+1)
  clear_selection(st)
  st.message=("Line %d"):format(st.row)
  st.messageTone="muted"
  return true
end

function M.new(ctx,opts)
  local st={
    title="Text Editor",icon="E",
    path=DEFAULT_PATH,
    lines={""},row=1,col=1,scroll=1,scrollX=0,
    dirty=false,message=nil,messageTone=nil,
    ctrl=false,shift=false,
    mode=nil,modeInput="",findTerm="",
    clipboard="",
    undo={},redo={},
    selAnchor=nil,selCursor=nil,mouseSelecting=false,
    pendingOpen=nil,confirmDiscard=false,
  }
  local path=opts and opts.path or st.path
  open_path(st,path,true)
  if opts then
    st.row=tonumber(opts.row) or st.row
    st.col=tonumber(opts.col) or st.col
    st.scroll=tonumber(opts.scroll) or st.scroll
    st.scrollX=tonumber(opts.scrollX) or st.scrollX
    clamp(st)
  end
  return st
end

function M.open(ctx,st,opts)
  if opts and opts.path then return open_path(st,opts.path,false) end
  return false
end

function M.snapshot(st)
  return {
    path=st.path,row=st.row,col=st.col,
    scroll=st.scroll,scrollX=st.scrollX,
  }
end

function M.get_title(st)
  return (st.dirty and "* " or "")..basename(st.path).." - Text Editor"
end

function M.before_close(ctx,st)
  if st.dirty then
    st.message="Unsaved changes - Ctrl+S save or Ctrl+Q twice to discard"
    st.messageTone="warning"
    return false
  end
  return true
end
local function selection_for_line(st,row,line)
  local first,last=ordered_selection(st)
  if not first or row<first.row or row>last.row then return nil,nil end
  local a=(row==first.row) and first.col or 1
  local b=(row==last.row) and (last.col-1) or #line
  a=math.max(1,a)
  b=math.max(a-1,math.min(#line,b))
  return a,b
end

function M.draw(ctx,st,ui,x,y,w,h,active)
  ui.fill(x,y,x+w-1,y+h-1,Theme.c.bg,Theme.c.text)

  local modeLabel=st.dirty and "MODIFIED" or "SAVED"
  Theme.header(ui,x,y,w,"File  Edit  Search",modeLabel)

  local contentY=y+1
  local footerY=y+h-1
  local rows=math.max(1,h-2)
  local gutter=(w>=28) and math.max(4,#tostring(#st.lines)+2) or 0
  local textCols=math.max(1,w-gutter)

  ensure_visible(st,rows,textCols)

  for screenRow=1,rows do
    local idx=st.scroll+screenRow-1
    local yy=contentY+screenRow-1
    ui.fill(x,yy,x+w-1,yy,Theme.c.bg,Theme.c.text)

    if idx<=#st.lines then
      local line=st.lines[idx] or ""
      if gutter>0 then
        local ln=("%"..tostring(gutter-1).."d "):format(idx)
        ui.text(x,yy,ln,idx==st.row and Theme.c.accent_alt or Theme.c.dim,Theme.c.bg)
      end

      local textX=x+gutter
      local visible=line:sub(st.scrollX+1,st.scrollX+textCols)
      ui.text(textX,yy,visible,Theme.c.text,Theme.c.bg)

      local sa,sb=selection_for_line(st,idx,line)
      if sa and sb and sb>=sa then
        local va=math.max(sa,st.scrollX+1)
        local vb=math.min(sb,st.scrollX+textCols)
        if vb>=va then
          local selected=line:sub(va,vb)
          ui.text(textX+(va-st.scrollX-1),yy,selected,Theme.c.selected_fg,Theme.c.selected_bg)
        end
      end
    end
  end

  local status=("Ln %d  Col %d  |  %d lines"):format(st.row,st.col,#st.lines)
  local right
  if st.mode=="find" then right="Find: "..st.modeInput.."_"
  elseif st.mode=="goto" then right="Go to line: "..st.modeInput.."_"
  elseif st.mode=="open" then right="Open: "..st.modeInput.."_"
  elseif st.mode=="saveas" then right="Save as: "..st.modeInput.."_"
  elseif st.mode=="confirm-open" then right="Unsaved: Y open / N cancel"
  else
    right=st.message or "Ctrl+S Save  Ctrl+F Find  Ctrl+G Go"
  end

  Theme.footer(ui,x,footerY,w,status)
  local maxRight=math.max(1,w-#status-4)
  right=Theme.fit(right,maxRight)
  local tone=st.messageTone
  local color=tone=="danger" and Theme.c.danger
    or tone=="warning" and Theme.c.warning
    or tone=="success" and Theme.c.success
    or Theme.c.muted
  ui.text(math.max(x+1,x+w-#right-1),footerY,right,color,Theme.c.surface)

  if active and not st.mode then
    local visibleRow=st.row-st.scroll
    local visibleCol=st.col-1-st.scrollX
    if visibleRow>=0 and visibleRow<rows and visibleCol>=0 and visibleCol<textCols then
      ui.cursor=x+gutter+visibleCol
      ui.cursor_y=contentY+visibleRow
    end
  end
end
local function handle_mode_key(st,a)
  if a==keys.escape then
    st.mode=nil;st.modeInput="";st.pendingOpen=nil
    st.message="Cancelled";st.messageTone="muted"
    return true
  elseif st.ctrl and a==keys.u then
    st.modeInput=""
    return true
  elseif a==keys.backspace then
    st.modeInput=st.modeInput:sub(1,-2)
    return true
  elseif a==keys.enter then
    local mode,input=st.mode,st.modeInput
    st.mode=nil;st.modeInput=""
    if mode=="find" then
      if input~="" then st.findTerm=input end
      find_next(st,st.findTerm,false)
    elseif mode=="goto" then
      goto_line(st,input)
    elseif mode=="open" then
      if input~="" then open_path(st,input,false) end
    elseif mode=="saveas" then
      if input~="" then save_file(st,input) end
    end
    return true
  end
  return false
end

local function set_mode(st,mode,initial)
  st.mode=mode
  st.modeInput=tostring(initial or "")
  st.message=nil;st.messageTone=nil
end

function M.event(ctx,st,ev,a,b,c,rx,ry,w,h)
  if ev=="key_up" then
    if a==keys.leftCtrl or a==keys.rightCtrl then st.ctrl=false end
    if a==keys.leftShift or a==keys.rightShift then st.shift=false end
    return false
  end

  if ev=="char" then
    local ch=tostring(a or "")
    if st.mode=="confirm-open" then
      ch=ch:lower()
      if ch=="y" then
        local path=st.pendingOpen
        st.pendingOpen=nil;st.mode=nil
        return open_path(st,path,true)
      elseif ch=="n" then
        st.pendingOpen=nil;st.mode=nil
        st.message="Open cancelled";st.messageTone="muted"
        return true
      end
      return true
    elseif st.mode then
      st.modeInput=st.modeInput..ch
      return true
    end
    insert_text(st,ch)
    return true
  end

  if ev=="paste" then
    if st.mode then st.modeInput=st.modeInput..tostring(a or "")
    else insert_text(st,tostring(a or "")) end
    return true
  end

  if ev=="key" then
    if a==keys.leftCtrl or a==keys.rightCtrl then st.ctrl=true;return true end
    if a==keys.leftShift or a==keys.rightShift then st.shift=true;return true end

    if st.mode and st.mode~="confirm-open" then
      return handle_mode_key(st,a)
    elseif st.mode=="confirm-open" then
      if a==keys.escape then
        st.pendingOpen=nil;st.mode=nil
        st.message="Open cancelled";st.messageTone="muted"
      end
      return true
    end

    if st.ctrl then
      if a==keys.s then
        if st.shift then set_mode(st,"saveas",st.path) else save_file(st) end
        return true
      elseif a==keys.o then set_mode(st,"open",st.path);return true
      elseif a==keys.f then set_mode(st,"find",st.findTerm);return true
      elseif a==keys.g then set_mode(st,"goto",tostring(st.row));return true
      elseif a==keys.z then undo(st);return true
      elseif a==keys.y then redo(st);return true
      elseif a==keys.a then
        st.selAnchor=pos(1,1)
        st.row=#st.lines;st.col=#(st.lines[#st.lines] or "")+1
        st.selCursor=pos(st.row,st.col)
        return true
      elseif a==keys.c then
        if has_selection(st) then
          st.clipboard=selected_text(st)
          st.message=("Copied %d chars"):format(#st.clipboard)
          st.messageTone="success"
        end
        return true
      elseif a==keys.x then
        if has_selection(st) then
          st.clipboard=selected_text(st)
          push_undo(st);delete_selection(st,true)
          st.message=("Cut %d chars"):format(#st.clipboard)
          st.messageTone="success"
        end
        return true
      elseif a==keys.v then
        if st.clipboard~="" then insert_text(st,st.clipboard) end
        return true
      elseif a==keys.q then
        if st.dirty and not st.confirmDiscard then
          st.confirmDiscard=true
          st.message="Press Ctrl+Q again to discard changes"
          st.messageTone="warning"
          return true
        end
        return {action="close_self",force=true}
      elseif a==keys.home then
        move_cursor(st,1,1,st.shift);return true
      elseif a==keys["end"] then
        local row=#st.lines
        move_cursor(st,row,#(st.lines[row] or "")+1,st.shift);return true
      end
    end

    local extend=st.shift
    if a==keys.left then
      local line=st.lines[st.row] or ""
      if st.ctrl then
        move_cursor(st,st.row,word_left(line,st.col),extend)
      elseif st.col>1 then
        move_cursor(st,st.row,st.col-1,extend)
      elseif st.row>1 then
        move_cursor(st,st.row-1,#(st.lines[st.row-1] or "")+1,extend)
      end
    elseif a==keys.right then
      local line=st.lines[st.row] or ""
      if st.ctrl then
        move_cursor(st,st.row,word_right(line,st.col),extend)
      elseif st.col<=#line then
        move_cursor(st,st.row,st.col+1,extend)
      elseif st.row<#st.lines then
        move_cursor(st,st.row+1,1,extend)
      end
    elseif a==keys.up then
      move_cursor(st,st.row-1,st.col,extend)
    elseif a==keys.down then
      move_cursor(st,st.row+1,st.col,extend)
    elseif a==keys.home then
      move_cursor(st,st.row,1,extend)
    elseif a==keys["end"] then
      move_cursor(st,st.row,#(st.lines[st.row] or "")+1,extend)
    elseif keys.pageUp and a==keys.pageUp then
      move_cursor(st,st.row-math.max(1,h-3),st.col,extend)
    elseif keys.pageDown and a==keys.pageDown then
      move_cursor(st,st.row+math.max(1,h-3),st.col,extend)
    elseif keys.f3 and a==keys.f3 then
      if st.findTerm~="" then find_next(st,st.findTerm,false) end
    elseif a==keys.backspace then
      backspace(st)
    elseif a==keys.delete then
      delete_forward(st)
    elseif a==keys.enter then
      local line=st.lines[st.row] or ""
      local indent=line:match("^(%s*)") or ""
      insert_text(st,"\n"..indent)
    elseif a==keys.tab then
      insert_text(st,TAB)
    elseif a==keys.f2 then
      save_file(st)
    else
      return false
    end
    clamp(st)
    return true
  end
  if ev=="mouse_click" and ry and ry>=2 and ry<=h-1 then
    local gutter=(w>=28) and math.max(4,#tostring(#st.lines)+2) or 0
    local row=st.scroll+ry-2
    if row>=1 and row<=#st.lines then
      local col=st.scrollX+math.max(1,(rx or 1)-gutter)
      col=math.min(#(st.lines[row] or "")+1,col)
      if st.shift and not st.selAnchor then st.selAnchor=pos(st.row,st.col) end
      if not st.shift then st.selAnchor=pos(row,col) end
      st.row=row;st.col=col
      st.selCursor=pos(row,col)
      st.mouseSelecting=true
      if not st.shift then
        -- A simple click should place the cursor, not leave a zero-width select.
        if st.selAnchor.row==st.selCursor.row and st.selAnchor.col==st.selCursor.col then
          st.selCursor=nil
        end
      end
      clamp(st)
      return true
    end
  end

  if ev=="mouse_drag" and st.mouseSelecting and ry then
    local gutter=(w>=28) and math.max(4,#tostring(#st.lines)+2) or 0
    local row=math.max(1,math.min(#st.lines,st.scroll+ry-2))
    local col=st.scrollX+math.max(1,(rx or 1)-gutter)
    col=math.min(#(st.lines[row] or "")+1,col)
    if not st.selAnchor then st.selAnchor=pos(st.row,st.col) end
    st.row=row;st.col=col
    st.selCursor=pos(row,col)
    clamp(st)
    return true
  end

  if ev=="mouse_up" then
    st.mouseSelecting=false
    return false
  end

  if ev=="mouse_scroll" then
    local delta=tonumber(a) or 0
    st.scroll=math.max(1,math.min(math.max(1,#st.lines),st.scroll+delta*3))
    return true
  end

  return false
end

return M
