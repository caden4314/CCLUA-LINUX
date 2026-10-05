local M={}
local config=dofile("/usr/lib/cclua/config.lua")
local systemApi=dofile("/usr/lib/cclua/api/system.lua")
local Theme=dofile("/usr/lib/cclua/desktop/theme.lua")

function M.new(ctx)
  return {title="Settings",icon="S",section=1}
end

local sections={"About","Network","Updates","Display"}

local function fit(value,width)
  local s=tostring(value or "")
  width=math.max(1,tonumber(width) or 1)
  if #s<=width then return s end
  if width==1 then return "~" end
  return s:sub(1,width-1).."~"
end

local function value_rows(ctx,section)
  local snapshot=systemApi.snapshot(ctx)
  local m=snapshot.machine
  if section==2 then
    local n=snapshot.network
    return {
      {"Hostname",m.hostname or "test-client"},
      {"Address",m.address or "unconfigured"},
      {"Network",m.network or "10.27.0.0/24"},
      {"Manager",m.manager or "10.27.0.1"},
      {"Link",n.state or "CHECKING"},
      {"RTT",(n.manager_rtt_ms and tostring(n.manager_rtt_ms).." ms") or "-"},
      {"Missed",tostring(n.missed_probes or 0)},
      {"Modems",tostring(n.modem_count or 0)},
      {"Reopens",tostring(n.reopen_count or 0)},
    }
  elseif section==3 then
    local u=snapshot.update
    return {
      {"State",u.state or "UNKNOWN"},
      {"Image",fit(u.current_commit or "?",18)},
      {"Available",fit(u.available_commit or "?",18)},
      {"Channel",m.channel or "development"},
      {"Auto update",u.auto_apply==false and "Off" or "On"},
      {"Manager",u.manager_state or "?"},
    }
  elseif section==4 then
    local w,h=term.getSize()
    return {
      {"Display","Advanced Computer"},
      {"Resolution",("%dx%d chars"):format(w,h)},
      {"Backend",m.display_backend or "computer-terminal"},
      {"External monitor",m.external_monitor_enabled and "Enabled" or "Disabled"},
      {"Desktop","CCLUA compositor"},
      {"Session","ubuntu"},
    }
  end
  return {
    {"OS","Ubuntu 22.04.5 LTS Desktop"},
    {"Device",snapshot.host.hostname},
    {"Computer ID",tostring(snapshot.host.computer_id)},
    {"Kernel",tostring(snapshot.system.kernel)},
    {"Kernel ABI",tostring(snapshot.system.kernel_abi)},
    {"Role",snapshot.host.role},
    {"POST",snapshot.post.state},
    {"Processes",tostring(snapshot.system.process_count)},
    {"User",snapshot.host.user},
  }
end

function M.draw(ctx,st,ui,x,y,w,h)
  ui.fill(x,y,x+w-1,y+h-1,Theme.c.bg,Theme.c.text)
  local bp=Theme.breakpoint(w,h)
  local contentX,contentY,contentW

  Theme.header(ui,x,y,w,"Settings",sections[st.section] or "About")

  if bp=="compact" then
    Theme.tabs(ui,x,y+1,w,sections,st.section)
    contentX=x+1
    contentY=y+3
    contentW=w-2
  else
    local side=math.min(16,math.max(12,math.floor(w*0.24)))
    ui.fill(x,y+1,x+side-1,y+h-2,Theme.c.surface,Theme.c.text)
    ui.text(x+1,y+1,"CATEGORIES",Theme.c.muted,Theme.c.surface)
    for i,label in ipairs(sections) do
      local yy=y+1+i
      Theme.list_row(ui,x,yy,side,label,i==st.section,i==st.section and nil or "muted")
    end
    contentX=x+side+2
    contentY=y+2
    contentW=w-side-3
  end

  Theme.section(ui,contentX,contentY,contentW,sections[st.section] or "About")
  local rows=value_rows(ctx,st.section)
  local yy=contentY+2
  for _,r in ipairs(rows) do
    if yy>y+h-2 then break end
    local tone=nil
    if r[1]=="Link" or r[1]=="State" or r[1]=="POST" or r[1]=="Manager" then tone=r[2] end
    Theme.kv(ui,contentX,yy,contentW,r[1],r[2],tone,math.min(14,math.max(9,math.floor(contentW*0.32))))
    yy=yy+1
  end

  Theme.footer(ui,x,y+h-1,w,bp=="compact" and "Left/Right category" or "Up/Down category","muted")
end

function M.event(ctx,st,ev,a,b,c,rx,ry,w,h)
  local compact=Theme.breakpoint(w,h)=="compact"
  if ev=="key" then
    if a==keys.up or (compact and a==keys.left) then
      st.section=math.max(1,st.section-1);return true
    end
    if a==keys.down or (compact and a==keys.right) then
      st.section=math.min(#sections,st.section+1);return true
    end
  elseif ev=="mouse_click" and rx and ry then
    if compact and ry==2 then
      local tx=1
      for i,label in ipairs(sections) do
        local width=#label+2
        if rx>=tx and rx<tx+width then st.section=i;return true end
        tx=tx+width+1
      end
    elseif not compact then
      local side=math.min(16,math.max(12,math.floor(w*0.24)))
      if rx<=side and ry>=3 and ry<=2+#sections then
        st.section=ry-2
        return true
      end
    end
  end
  return false
end

return M
