local M={}

M.c={
  bg=colors.black,
  surface=colors.gray,
  surface_alt=colors.black,
  text=colors.white,
  muted=colors.lightGray,
  dim=colors.gray,
  accent=colors.orange,
  accent_alt=colors.cyan,
  success=colors.lime,
  warning=colors.yellow,
  danger=colors.red,
  selected_bg=colors.lightGray,
  selected_fg=colors.black,
}

function M.fit(value,width)
  local s=tostring(value or "")
  width=math.max(0,tonumber(width) or 0)
  if width<=0 then return "" end
  if #s<=width then return s end
  if width<=1 then return "~" end
  return s:sub(1,width-1).."~"
end
function M.breakpoint(w,h)
  w=tonumber(w) or 0
  h=tonumber(h) or 0
  if w<44 or h<15 then return "compact" end
  if w>=72 and h>=24 then return "wide" end
  return "regular"
end

function M.state_color(state)
  state=tostring(state or ""):upper()
  if state=="HEALTHY" or state=="ONLINE" or state=="CURRENT"
    or state=="PASSED" or state=="ACTIVE" or state=="RUNNING"
    or state=="READY" or state=="ON" then
    return M.c.success
  end
  if state=="FAILED" or state=="DEGRADED" or state=="OFFLINE"
    or state=="NO_MODEM" or state=="ERROR" or state=="FAULT" then
    return M.c.danger
  end
  if state=="BOOTING" or state=="UPDATING" or state=="CHECKING"
    or state=="STAGING" or state=="VERIFYING" or state=="ACTIVATING"
    or state=="DOWNLOADING" or state=="AVAILABLE" then
    return M.c.warning
  end
  return M.c.muted
end
function M.header(ui,x,y,w,title,meta)
  ui.fill(x,y,x+w-1,y,M.c.surface,M.c.text)
  ui.text(x+1,y,M.fit(title,math.max(1,w-2)),M.c.text,M.c.surface)
  if meta and meta~="" then
    meta=tostring(meta)
    local mx=x+w-#meta-1
    if mx>x+#tostring(title)+2 then
      ui.text(mx,y,M.fit(meta,w-2),M.c.muted,M.c.surface)
    end
  end
end

function M.section(ui,x,y,w,title)
  ui.text(x,y,M.fit(tostring(title or ""):upper(),w),M.c.accent_alt,M.c.bg)
end

function M.tabs(ui,x,y,w,labels,active)
  ui.fill(x,y,x+w-1,y,M.c.bg,M.c.text)
  local tx=x
  for i,label in ipairs(labels or {}) do
    local text=" "..tostring(label).." "
    local bg=i==active and M.c.surface or M.c.bg
    local fg=i==active and M.c.text or M.c.muted
    if tx+#text-1>x+w-1 then break end
    ui.text(tx,y,text,fg,bg)
    tx=tx+#text+1
  end
end
function M.footer(ui,x,y,w,text,tone)
  local fg=M.c.muted
  if tone=="success" then fg=M.c.success
  elseif tone=="warning" then fg=M.c.warning
  elseif tone=="danger" then fg=M.c.danger
  elseif tone=="accent" then fg=M.c.accent end
  ui.fill(x,y,x+w-1,y,M.c.surface,M.c.text)
  ui.text(x+1,y,M.fit(text,math.max(1,w-2)),fg,M.c.surface)
end

function M.list_row(ui,x,y,w,text,selected,tone)
  local bg=selected and M.c.selected_bg or M.c.bg
  local fg=selected and M.c.selected_fg or M.c.text
  if not selected then
    if tone=="success" then fg=M.c.success
    elseif tone=="warning" then fg=M.c.warning
    elseif tone=="danger" then fg=M.c.danger
    elseif tone=="muted" then fg=M.c.muted
    elseif tone=="accent" then fg=M.c.accent_alt end
  end
  ui.fill(x,y,x+w-1,y,bg,fg)
  ui.text(x+1,y,M.fit(text,math.max(1,w-2)),fg,bg)
end

function M.kv(ui,x,y,w,label,value,tone,labelWidth)
  labelWidth=math.min(labelWidth or 12,math.max(7,w-4))
  ui.text(x,y,M.fit(label,labelWidth-1),M.c.dim,M.c.bg)
  local fg=tone and M.state_color(tone) or M.c.text
  ui.text(x+labelWidth,y,M.fit(value,math.max(1,w-labelWidth)),fg,M.c.bg)
end

return M
