local M={}
local pkgdb=dofile("/usr/lib/cclua/package_db.lua")
local Theme=dofile("/usr/lib/cclua/desktop/theme.lua")

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
  ui.fill(x,y,x+w-1,y+h-1,Theme.c.bg,Theme.c.text)
  local list=results(st);st._results=list
  Theme.header(ui,x,y,w,"Software",("%d matches"):format(#list))
  ui.fill(x+1,y+1,x+w-2,y+1,Theme.c.surface,Theme.c.text)
  local query=st.query=="" and "Search packages..." or st.query
  ui.text(x+2,y+1,Theme.fit(query,math.max(1,w-4)),
    st.query=="" and Theme.c.muted or Theme.c.text,Theme.c.surface)
  Theme.section(ui,x+1,y+2,w-2,"Ubuntu 22.04.5 Desktop packages")
  local body=math.max(1,h-5)
  for i=1,math.min(body,#list) do
    local p=list[i]
    local bg=i==st.selected and colors.lightGray or colors.black
    local fg=i==st.selected and colors.black or colors.white
    ui.fill(x,y+i+2,x+w-1,y+i+2,bg,fg)
    local ver=tostring(p.version or "?")
    local verWidth=math.min(13,math.max(8,math.floor(w*0.32)))
    if #ver>verWidth then ver=ver:sub(1,verWidth-1).."~" end
    local nameWidth=math.max(8,w-verWidth-4)
    local name=p.name
    if #name>nameWidth then name=name:sub(1,nameWidth-1).."~" end
    ui.text(x+1,y+i+2,name,fg,bg)
    ui.text(x+w-verWidth-1,y+i+2,ver,fg,bg)
  end

  local selected=list[st.selected]
  local footer=("%d matches"):format(#list)
  if selected then footer=footer.."  |  "..selected.name.."  |  Up/Down select" end
  Theme.footer(ui,x,y+h-1,w,footer)
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
