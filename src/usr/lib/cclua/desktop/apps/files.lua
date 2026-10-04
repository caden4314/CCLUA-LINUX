local M={}

local function host(path)
  local p=tostring(path or ""):gsub("^/","")
  return p=="" and "/" or p
end

local function norm(path)
  if path=="" then return "/" end
  if path:sub(1,1)~="/" then path="/"..path end
  local out={}
  for part in path:gmatch("[^/]+") do
    if part==".." then table.remove(out)
    elseif part~="." and part~="" then out[#out+1]=part end
  end
  return "/"..table.concat(out,"/")
end

local function parent(path)
  path=norm(path)
  if path=="/" then return "/" end
  return norm(path.."/..")
end

local function format_size(n)
  n=tonumber(n) or 0
  if n<1024 then return tostring(n).." B" end
  if n<1024*1024 then return ("%.1f K"):format(n/1024) end
  return ("%.1f M"):format(n/(1024*1024))
end

local function entries(path)
  local ok,list=pcall(fs.list,host(path))
  if not ok then return {} end
  table.sort(list,function(a,b)
    local ad=fs.isDir(fs.combine(host(path),a))
    local bd=fs.isDir(fs.combine(host(path),b))
    if ad~=bd then return ad end
    return a:lower()<b:lower()
  end)
  return list
end

function M.new(ctx,opts)
  return {
    title="Files",icon="F",
    path=opts and opts.path or "/home/caden",
    selected=1,offset=1,
    sidebar=1,
  }
end

function M.open(ctx,st,opts)
  if opts and opts.path then
    local p=norm(opts.path)
    if fs.exists(host(p)) and fs.isDir(host(p)) then
      st.path=p;st.selected=1;st.offset=1
      return true
    end
  end
  return false
end

function M.snapshot(st)
  return {path=st.path}
end

local sidebar={
  {"Home","/home/caden"},
  {"Root","/"},
  {"etc","/etc"},
  {"usr","/usr"},
  {"var","/var"},
}

function M.draw(ctx,st,ui,x,y,w,h)
  ui.fill(x,y,x+w-1,y+h-1,colors.black,colors.white)

  local sideW=math.min(10,math.max(8,math.floor(w*0.24)))
  local listX=x+sideW+1
  local listW=w-sideW-1

  ui.fill(x,y,x+w-1,y,colors.gray,colors.white)
  ui.text(x+1,y,"<",colors.lightGray,colors.gray)
  local crumb=st.path
  if #crumb>listW-2 then crumb="~"..crumb:sub(-(listW-3)) end
  ui.text(listX,y,crumb:sub(1,listW-1),colors.white,colors.gray)

  ui.fill(x,y+1,x+sideW-1,y+h-2,colors.gray,colors.white)
  ui.text(x+1,y+1,"Places",colors.lightGray,colors.gray)
  for i,item in ipairs(sidebar) do
    local yy=y+1+i
    if yy<=y+h-2 then
      local active=st.path==item[2] or (item[2]~="/" and st.path:sub(1,#item[2])==item[2])
      local bg=active and colors.lightGray or colors.gray
      local fg=active and colors.black or colors.white
      ui.fill(x,yy,x+sideW-1,yy,bg,fg)
      ui.text(x+1,yy,item[1]:sub(1,sideW-2),fg,bg)
    end
  end

  local list=entries(st.path)
  st._entries=list
  st.selected=math.max(1,math.min(math.max(1,#list),st.selected))
  local rows=math.max(1,h-3)
  if st.selected<st.offset then st.offset=st.selected end
  if st.selected>=st.offset+rows then st.offset=st.selected-rows+1 end

  for row=1,rows do
    local idx=st.offset+row-1
    local yy=y+row
    local name=list[idx]
    ui.fill(listX,yy,x+w-1,yy,colors.black,colors.white)
    if name then
      local full=fs.combine(host(st.path),name)
      local dir=fs.isDir(full)
      local bg=idx==st.selected and colors.lightGray or colors.black
      local fg=idx==st.selected and colors.black or (dir and colors.cyan or colors.white)
      ui.fill(listX,yy,x+w-1,yy,bg,fg)
      local icon=dir and "/" or "-"
      local size=dir and "" or format_size(fs.getSize(full))
      local avail=math.max(4,listW-#size-4)
      local display=name
      if #display>avail then display=display:sub(1,avail-1).."~" end
      ui.text(listX+1,yy,icon.." "..display,fg,bg)
      if size~="" and #size<listW-3 then
        ui.text(x+w-#size-1,yy,size,fg,bg)
      end
    end
  end

  ui.fill(x,y+h-1,x+w-1,y+h-1,colors.gray,colors.white)
  local selected=list[st.selected]
  local msg
  if selected then
    local full=fs.combine(host(st.path),selected)
    msg=fs.isDir(full) and ("Folder  "..selected) or (selected.."  "..format_size(fs.getSize(full)).."  Enter opens")
  else
    msg=#list.." items"
  end
  ui.text(x+1,y+h-1,msg:sub(1,w-2),colors.lightGray,colors.gray)
end

local function open_selected(st)
  local name=(st._entries or {})[st.selected]
  if not name then return nil end
  local full=norm(st.path.."/"..name)
  if fs.isDir(host(full)) then
    st.path=full;st.selected=1;st.offset=1
    return true
  end
  return {action="open_app",app="editor",path=full}
end

function M.event(ctx,st,ev,a,b,c,rx,ry,w,h)
  if ev=="key" then
    if a==keys.up then st.selected=math.max(1,st.selected-1);return true end
    if a==keys.down then st.selected=math.min(math.max(1,#(st._entries or {})),st.selected+1);return true end
    if a==keys.enter or a==keys.right then return open_selected(st) end
    if a==keys.backspace or a==keys.left then
      st.path=parent(st.path);st.selected=1;st.offset=1;return true
    end
    if a==keys.home then st.path="/home/caden";st.selected=1;st.offset=1;return true end
  elseif ev=="mouse_click" and rx and ry then
    local sideW=math.min(10,math.max(8,math.floor(w*0.24)))
    if ry==1 and rx<=3 then
      st.path=parent(st.path);st.selected=1;st.offset=1;return true
    end
    if rx<=sideW and ry>=3 then
      local idx=ry-2
      local item=sidebar[idx]
      if item then st.path=item[2];st.selected=1;st.offset=1;return true end
    elseif rx>sideW and ry>=2 and ry<=h-1 then
      local idx=st.offset+ry-2
      if (st._entries or {})[idx] then
        if st.selected==idx then return open_selected(st) end
        st.selected=idx
        return true
      end
    end
  elseif ev=="mouse_scroll" then
    st.selected=math.max(1,math.min(math.max(1,#(st._entries or {})),st.selected+(tonumber(a) or 0)))
    return true
  end
  return false
end

return M
