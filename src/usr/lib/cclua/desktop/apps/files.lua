local M={}

local function host(path)
  local p=tostring(path):gsub("^/","")
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

function M.new(ctx)
  return {title="Files",icon="[]",path="/home/caden",selected=1,offset=1}
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

function M.draw(ctx,st,ui,x,y,w,h)
  ui.fill(x,y,x+w-1,y+h-1,colors.black,colors.white)
  ui.fill(x,y,x+w-1,y,colors.gray,colors.white)
  ui.text(x+1,y,st.path:sub(1,w-2),colors.white,colors.gray)
  local list=entries(st.path)
  st._entries=list
  local rows=h-1
  if st.selected<st.offset then st.offset=st.selected end
  if st.selected>=st.offset+rows then st.offset=st.selected-rows+1 end
  for row=1,rows do
    local idx=st.offset+row-1
    local name=list[idx]
    if name then
      local full=fs.combine(host(st.path),name)
      local dir=fs.isDir(full)
      local bg=idx==st.selected and colors.lightGray or colors.black
      local fg=idx==st.selected and colors.black or (dir and colors.cyan or colors.white)
      ui.fill(x,y+row,x+w-1,y+row,bg,fg)
      ui.text(x+1,y+row,(dir and "[D] " or "    ")..name:sub(1,w-6),fg,bg)
    end
  end
end

local function open_selected(st)
  local name=(st._entries or {})[st.selected]
  if not name then return end
  local full=norm(st.path.."/"..name)
  if fs.isDir(host(full)) then st.path=full;st.selected=1;st.offset=1 end
end

function M.event(ctx,st,ev,a,b,c,rx,ry,w,h)
  if ev=="key" then
    if a==keys.up then st.selected=math.max(1,st.selected-1);return true end
    if a==keys.down then st.selected=math.min(math.max(1,#(st._entries or {})),st.selected+1);return true end
    if a==keys.enter or a==keys.right then open_selected(st);return true end
    if a==keys.backspace or a==keys.left then
      st.path=norm(st.path.."/..");st.selected=1;st.offset=1;return true
    end
  elseif ev=="mouse_click" and ry and ry>=2 and ry<=h then
    local idx=st.offset+ry-2
    if (st._entries or {})[idx] then
      if st.selected==idx then open_selected(st) else st.selected=idx end
      return true
    end
  elseif ev=="mouse_scroll" then
    st.selected=math.max(1,math.min(#(st._entries or {}),st.selected+(a or 0)))
    return true
  end
  return false
end

return M
