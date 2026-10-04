local M={}
local config=dofile("/usr/lib/cclua/config.lua")

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
  local m=config.machine()
  if section==2 then
    return {
      {"Hostname",m.hostname or "test-client"},
      {"Address",m.address or "unconfigured"},
      {"Netmask",m.netmask or "255.255.255.0"},
      {"Manager",m.manager or "10.27.0.1"},
      {"Network",m.network or "10.27.0.0/24"},
      {"Status","Connected"},
    }
  elseif section==3 then
    local u=config.read_json("/var/lib/cclua/update-state.json",{})
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
    {"Device",m.hostname or "test-client"},
    {"Computer ID",tostring(os.getComputerID())},
    {"Kernel",tostring(ctx.kernel.version.version)},
    {"Kernel ABI",tostring(ctx.kernel.version.kernel_abi)},
    {"Role",m.role or "desktop-client"},
    {"Processes",tostring(#ctx.kernel.process.all())},
    {"User","caden"},
  }
end

function M.draw(ctx,st,ui,x,y,w,h)
  ui.fill(x,y,x+w-1,y+h-1,colors.black,colors.white)
  local side=math.min(12,math.max(10,math.floor(w*0.28)))
  ui.fill(x,y,x+side-1,y+h-1,colors.gray,colors.white)

  ui.text(x+1,y,"Settings",colors.white,colors.gray)
  for i,label in ipairs(sections) do
    local yy=y+1+i
    local active=i==st.section
    local bg=active and colors.lightGray or colors.gray
    local fg=active and colors.black or colors.white
    ui.fill(x,yy,x+side-1,yy,bg,fg)
    ui.text(x+1,yy,label:sub(1,side-2),fg,bg)
  end

  local contentX=x+side+1
  local contentW=w-side-1
  local heading=sections[st.section] or "About"
  ui.text(contentX,y+1,heading,colors.orange,colors.black)

  local rows=value_rows(ctx,st.section)
  local yy=y+3
  for _,r in ipairs(rows) do
    if yy>y+h-2 then break end
    local labelW=math.min(11,math.max(8,math.floor(contentW*0.34)))
    local valueW=math.max(1,contentW-labelW-1)
    ui.text(contentX,yy,fit(r[1],labelW-1),colors.gray,colors.black)
    ui.text(contentX+labelW,yy,fit(r[2],valueW),colors.white,colors.black)
    yy=yy+1
  end

  ui.fill(contentX,y+h-1,x+w-1,y+h-1,colors.gray,colors.white)
  ui.text(contentX+1,y+h-1,"Up/Down section",colors.lightGray,colors.gray)
end

function M.event(ctx,st,ev,a,b,c,rx,ry,w,h)
  if ev=="key" then
    if a==keys.up then st.section=math.max(1,st.section-1);return true end
    if a==keys.down then st.section=math.min(#sections,st.section+1);return true end
  elseif ev=="mouse_click" and rx and ry then
    local side=math.min(12,math.max(10,math.floor(w*0.28)))
    if rx<=side and ry>=3 and ry<=2+#sections then
      st.section=ry-2
      return true
    end
  end
  return false
end

return M
