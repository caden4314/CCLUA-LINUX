local M={}
local config=dofile("/usr/lib/cclua/config.lua")
local TABS={"Processes","Services","Devices","Health"}

function M.new(ctx)
  return {title="System Monitor",icon="M",tab=1,selected=1,scroll=1}
end

local function process_rows(ctx)
  local out={}
  for _,p in ipairs(ctx.kernel.process.all()) do
    out[#out+1]={
      a=tostring(p.pid or "?"),
      b=tostring(p.name or p.argv and p.argv[1] or "process"),
      c=tostring(p.state or "?"),
    }
  end
  table.sort(out,function(x,y)return tonumber(x.a) and tonumber(y.a) and tonumber(x.a)<tonumber(y.a) or x.a<y.a end)
  return out
end

local function service_rows(ctx)
  local out={}
  for _,s in ipairs(ctx.kernel.services:list()) do
    out[#out+1]={
      a=tostring(s.name or "?"),
      b=tostring(s.state or "?"),
      c=tostring(s.pid or "-"),
    }
  end
  table.sort(out,function(x,y)return x.a<y.a end)
  return out
end

local function peripheral_rows(ctx)
  local out={}
  for name,dev in pairs(ctx.kernel.device.devices or {}) do
    local t=dev.type or dev.types or "peripheral"
    if type(t)=="table" then t=table.concat(t,",") end
    out[#out+1]={a=tostring(name),b=tostring(t),c=""}
  end
  table.sort(out,function(x,y)return x.a<y.a end)
  return out
end

local function health_rows(ctx)
  local post=config.read_json("/var/lib/cclua/post.json",{})
  local net=config.read_json("/var/lib/cclua/network-health.json",{})
  local status=config.read_json("/var/lib/cclua/status.json",{})
  local update=config.read_json("/var/lib/cclua/update-state.json",{})
  local session=config.read_json("/var/lib/cclua/session-health.json",{})
  local restarts=0
  local failed=0
  for _,u in ipairs(ctx.kernel.services:list()) do
    restarts=restarts+(tonumber(u.total_restarts) or 0)
    if u.state=="failed" then failed=failed+1 end
  end

  local function row(a,b,c) return {a=tostring(a),b=tostring(b or "-"),c=tostring(c or "")} end
  return {
    row("System",status.state or "BOOTING",status.error_reason or ""),
    row("POST",post.state or "UNKNOWN",
      ("%s pass / %s warn / %s fail"):format(post.pass or 0,post.warn or 0,post.fail or 0)),
    row("Network",net.state or "UNKNOWN",
      ("RTT %sms / missed %s"):format(net.manager_rtt_ms or "-",net.missed_probes or 0)),
    row("Modems",net.modem_count or 0,
      ("reopens %s"):format(net.reopen_count or 0)),
    row("Manager age",net.manager_age_seconds and string.format("%.1fs",net.manager_age_seconds) or "-",""),
    row("Update",update.state or update.phase or "IDLE",
      tostring(update.current_commit or "-"):sub(1,16)),
    row("Session",session.mode or "-",
      session.recovery and "RECOVERY" or ("crash streak "..tostring(session.crash_streak or 0))),
    row("Services",#ctx.kernel.services:list(),
      ("%d failed / %d restarts"):format(failed,restarts)),
  }
end

local function rows(ctx,tab)
  if tab==2 then return service_rows(ctx) end
  if tab==3 then return peripheral_rows(ctx) end
  if tab==4 then return health_rows(ctx) end
  return process_rows(ctx)
end

function M.draw(ctx,st,ui,x,y,w,h)
  ui.fill(x,y,x+w-1,y+h-1,colors.black,colors.white)

  local tx=x+1
  for i,label in ipairs(TABS) do
    local bg=i==st.tab and colors.gray or colors.black
    local fg=i==st.tab and colors.white or colors.lightGray
    ui.text(tx,y," "..label.." ",fg,bg)
    tx=tx+#label+3
  end

  local list=rows(ctx,st.tab)
  st._rows=list
  st.selected=math.max(1,math.min(math.max(1,#list),st.selected))
  local body=math.max(1,h-2)
  if st.selected<st.scroll then st.scroll=st.selected end
  if st.selected>=st.scroll+body then st.scroll=st.selected-body+1 end

  local header
  if st.tab==1 then header="PID   NAME                       STATE"
  elseif st.tab==2 then header="SERVICE                        STATE   PID"
  elseif st.tab==3 then header="DEVICE                         TYPE"
  else header="CHECK                          STATE        DETAIL" end
  ui.text(x+1,y+1,header:sub(1,math.max(1,w-2)),colors.gray,colors.black)

  for line=1,body-1 do
    local idx=st.scroll+line-1
    local item=list[idx]
    local yy=y+1+line
    ui.fill(x,yy,x+w-1,yy,colors.black,colors.white)
    if item then
      local bg=idx==st.selected and colors.lightGray or colors.black
      local fg=idx==st.selected and colors.black or colors.white
      ui.fill(x,yy,x+w-1,yy,bg,fg)
      local text
      if st.tab==1 then
        text=("%-5s %-26s %s"):format(item.a,item.b:sub(1,26),item.c)
      elseif st.tab==2 then
        text=("%-30s %-7s %s"):format(item.a:sub(1,30),item.b,item.c)
      elseif st.tab==3 then
        text=("%-30s %s"):format(item.a:sub(1,30),item.b)
      else
        text=("%-28s %-12s %s"):format(item.a:sub(1,28),item.b:sub(1,12),item.c)
      end
      ui.text(x+1,yy,text:sub(1,math.max(1,w-2)),fg,bg)
    end
  end

  local footer=(" %d items  Tab changes view "):format(#list)
  ui.fill(x,y+h-1,x+w-1,y+h-1,colors.gray,colors.white)
  ui.text(x,y+h-1,footer:sub(1,w),colors.lightGray,colors.gray)
end

local function tab_at(rx)
  local x=2
  for i,label in ipairs(TABS) do
    local width=#label+2
    if rx and rx>=x and rx<x+width then return i end
    x=x+width+1
  end
  return nil
end

function M.event(ctx,st,ev,a,b,c,rx,ry,w,h)
  if ev=="key" then
    if a==keys.tab then st.tab=st.tab%#TABS+1;st.selected=1;st.scroll=1;return true end
    if a==keys.up then st.selected=math.max(1,st.selected-1);return true end
    if a==keys.down then st.selected=math.min(math.max(1,#(st._rows or {})),st.selected+1);return true end
  elseif ev=="mouse_click" and ry then
    if ry==1 then
      local selected=tab_at(rx)
      if selected then st.tab=selected;st.selected=1;st.scroll=1;return true end
    elseif ry>=3 and ry<h then
      local idx=st.scroll+ry-3
      if (st._rows or {})[idx] then st.selected=idx;return true end
    end
  elseif ev=="mouse_scroll" then
    st.selected=math.max(1,math.min(math.max(1,#(st._rows or {})),st.selected+(tonumber(a) or 0)))
    return true
  end
  return false
end

return M
