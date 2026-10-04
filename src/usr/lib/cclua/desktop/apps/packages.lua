local M={}
local pkgdb=dofile("/usr/lib/cclua/package_db.lua")

function M.new(ctx)
  return {title="Ubuntu Software",icon="#",query="",selected=1}
end

local function results(st)
  local out={}
  local q=st.query:lower()
  for _,p in ipairs(pkgdb.load().packages or {}) do
    if q=="" or p.name:lower():find(q,1,true) then
      out[#out+1]=p
      if #out>=100 then break end
    end
  end
  return out
end

function M.draw(ctx,st,ui,x,y,w,h)
  ui.fill(x,y,x+w-1,y+h-1,colors.black,colors.white)
  ui.fill(x,y,x+w-1,y+1,colors.gray,colors.white)
  ui.text(x+1,y,"Search: "..st.query,colors.white,colors.gray)
  ui.text(x+1,y+1,"Ubuntu 22.04.5 Desktop packages",colors.lightGray,colors.gray)
  local list=results(st);st._results=list
  for i=1,math.min(h-2,#list) do
    local p=list[i]
    local bg=i==st.selected and colors.lightGray or colors.black
    local fg=i==st.selected and colors.black or colors.white
    ui.fill(x,y+i+1,x+w-1,y+i+1,bg,fg)
    ui.text(x+1,y+i+1,p.name:sub(1,math.max(1,w-18)),fg,bg)
    local ver=tostring(p.version or "?")
    ui.text(math.max(x+1,x+w-#ver-1),y+i+1,ver:sub(1,w-2),fg,bg)
  end
end

function M.event(ctx,st,ev,a)
  if ev=="char" then st.query=st.query..tostring(a);st.selected=1;return true end
  if ev=="key" then
    if a==keys.backspace then st.query=st.query:sub(1,-2);st.selected=1;return true end
    if a==keys.up then st.selected=math.max(1,st.selected-1);return true end
    if a==keys.down then st.selected=math.min(math.max(1,#(st._results or {})),st.selected+1);return true end
  end
  return false
end

return M
