local M={}
local pkgdb=dofile("/usr/lib/cclua/package_db.lua")
local Theme=dofile("/usr/lib/cclua/desktop/theme.lua")

function M.new(ctx)
  return {title="Ubuntu Software",icon="#",query="",selected=1,native_only=false}
end

local function results(st)
  return pkgdb.search(st.query or "",{implemented_only=st.native_only==true})
end

function M.draw(ctx,st,ui,x,y,w,h)
  ui.fill(x,y,x+w-1,y+h-1,Theme.c.bg,Theme.c.text)
  local list=results(st);st._results=list
  local meta=pkgdb.load()
  local mode=st.native_only and "Native only" or "Native + Ubuntu reference"
  Theme.header(ui,x,y,w,"Software",mode)

  ui.fill(x+1,y+1,x+w-2,y+1,Theme.c.surface,Theme.c.text)
  local query=st.query=="" and "Search software..." or st.query
  ui.text(x+2,y+1,Theme.fit(query,math.max(1,w-4)),
    st.query=="" and Theme.c.muted or Theme.c.text,Theme.c.surface)

  Theme.section(ui,x+1,y+2,w-2,
    ("CCLUA native %d  |  Ubuntu reference %d"):format(
      meta.implemented_count or 0,meta.reference_count or 0))

  local body=math.max(1,h-6)
  local maxRows=math.min(body,#list)
  local start=1
  if st.selected>maxRows then start=st.selected-maxRows+1 end

  for row=1,maxRows do
    local i=start+row-1
    local p=list[i]
    if not p then break end
    local selected=i==st.selected
    local bg=selected and colors.lightGray or colors.black
    local fg=selected and colors.black or colors.white
    ui.fill(x,y+row+2,x+w-1,y+row+2,bg,fg)

    local native=p.implementation=="native"
    local tag=native and "NATIVE" or "REF"
    local tagWidth=6
    local ver=tostring(p.version or "?")
    local verWidth=math.min(13,math.max(8,math.floor(w*0.25)))
    if #ver>verWidth then ver=ver:sub(1,verWidth-1).."~" end
    local nameWidth=math.max(8,w-verWidth-tagWidth-5)
    local name=tostring(p.name or "-")
    if #name>nameWidth then name=name:sub(1,nameWidth-1).."~" end

    ui.text(x+1,y+row+2,name,fg,bg)
    ui.text(x+w-verWidth-tagWidth-2,y+row+2,tag,
      selected and fg or (native and colors.lime or colors.gray),bg)
    ui.text(x+w-verWidth-1,y+row+2,ver,fg,bg)
  end

  local selected=list[st.selected]
  local footer=("Tab: %s  |  %d results"):format(
    st.native_only and "show all" or "native only",#list)
  if selected then
    local detail=selected.implementation=="native"
      and ("Runnable: "..table.concat(selected.commands or {},", "))
      or "Ubuntu compatibility metadata; not runnable yet"
    footer=detail.."  |  Tab filter"
  end
  Theme.footer(ui,x,y+h-1,w,Theme.fit(footer,w))
end

function M.event(ctx,st,ev,a)
  if ev=="char" then
    st.query=st.query..tostring(a);st.selected=1;return true
  end
  if ev=="key" then
    if a==keys.backspace then
      st.query=st.query:sub(1,-2);st.selected=1;return true
    end
    if a==keys.up then
      st.selected=math.max(1,st.selected-1);return true
    end
    if a==keys.down then
      st.selected=math.min(math.max(1,#(st._results or {})),st.selected+1);return true
    end
    if a==keys.tab then
      st.native_only=not st.native_only
      st.selected=1
      return true
    end
  end
  return false
end

return M
