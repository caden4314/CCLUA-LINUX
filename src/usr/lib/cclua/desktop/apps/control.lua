local M={}
local admin=dofile("/usr/lib/cclua/admin.lua")
local Theme=dofile("/usr/lib/cclua/desktop/theme.lua")

local tabs={"Fleet","GPS","Lights"}

local SERVICE_BY_ROLE={
  ["lighting-controller"]="cclua-lightingd.service",
  ["gps-control"]="cclua-gps-control.service",
  ["gps-monitor"]="cclua-gps-monitor.service",
  ["gps-host"]="cclua-gps-host.service",
  ["fleet-monitor"]="cclua-server-room-monitor.service",
  ["app-server"]="cclua-apphostd.service",
  ["desktop-client"]="cclua-controld.service",
}

function M.new(ctx)
  return {
    title="Control Center",icon="CC",
    tab=1,selected=1,
    fleet=nil,gps=nil,lights=nil,
    message="R refresh"
  }
end

local function age_seconds(ms)
  if not ms then return math.huge end
  local now=os.epoch and os.epoch("utc") or 0
  return math.max(0,(now-tonumber(ms or 0))/1000)
end

local function refresh_fleet(st)
  local data,err=admin.snapshot()
  if not data then st.message=tostring(err);return false end
  st.fleet=data.fleet or {nodes={}}
  st.selected=math.max(1,math.min(math.max(1,#(st.fleet.nodes or {})),st.selected))
  st.message="Fleet refreshed"
  return true
end

local function refresh_gps(st)
  local data,err=admin.gps({op="status"})
  if not data then st.message=tostring(err);return false end
  st.gps=data.state or data
  st.selected=1
  st.message="GPS refreshed"
  return true
end

local function refresh_lights(st)
  local data,err=admin.lighting({op="status"})
  if not data then st.message=tostring(err);return false end
  st.lights=data.state or data
  st.selected=math.max(1,math.min(math.max(1,#(st.lights.rooms or {})),st.selected))
  st.message="Lighting refreshed"
  return true
end

local function refresh(st)
  if st.tab==1 then return refresh_fleet(st) end
  if st.tab==2 then return refresh_gps(st) end
  return refresh_lights(st)
end

local function fleet_rows(st)
  return st.fleet and st.fleet.nodes or {}
end

local function gps_rows(st)
  local out={}
  if st.gps then
    for _,h in ipairs(st.gps.hosts or {}) do
      out[#out+1]={kind="host",data=h}
    end
    for _,c in ipairs(st.gps.clients or {}) do
      out[#out+1]={kind="client",data=c}
    end
  end
  return out
end

local function light_rows(st)
  return st.lights and st.lights.rooms or {}
end

local function state_color(state,online)
  if online==false then return colors.red end
  state=tostring(state or ""):upper()
  if state=="HEALTHY" or state=="CURRENT" or state=="ON" or state=="READY" then return colors.lime end
  if state=="OFF" then return colors.lightGray end
  if state=="MISSING" or state=="FAILED" or state=="DEGRADED" or state=="OFFLINE" then return colors.red end
  return colors.yellow
end

local function draw_tabs(st,ui,x,y,w)
  Theme.tabs(ui,x,y,w,tabs,st.tab)
end

function M.draw(ctx,st,ui,x,y,w,h)
  ui.fill(x,y,x+w-1,y+h-1,colors.black,colors.white)
  draw_tabs(st,ui,x,y,w)

  if st.tab==1 then
    local rows=fleet_rows(st)
    st._rows=rows
    ui.text(x+1,y+1,"ID  HOST              ROLE           STATE",colors.gray,colors.black)
    local maxRows=math.max(1,h-4)
    for i=1,math.min(maxRows,#rows) do
      local n=rows[i]
      local s=n.status or {}
      local online=age_seconds(n.last_seen)<30
      local state=online and tostring(s.system_state or "BOOTING") or "OFFLINE"
      local yy=y+1+i
      local bg=i==st.selected and colors.lightGray or colors.black
      local fg=i==st.selected and colors.black or state_color(state,online)
      ui.fill(x,yy,x+w-1,yy,bg,fg)
      local line=("%-3s %-17s %-14s %s"):format(
        tostring(n.id or "-"),
        tostring(n.hostname or "-"):sub(1,17),
        tostring(n.role or s.role or "-"):sub(1,14),
        state
      )
      ui.text(x+1,yy,line:sub(1,math.max(1,w-2)),fg,bg)
    end

    if #rows==0 then ui.text(x+1,y+3,"No fleet snapshot. Press R.",colors.gray,colors.black) end
    ui.text(x+1,y+h-2,"Enter restart role service | B reboot | R refresh",colors.gray,colors.black)

  elseif st.tab==2 then
    local g=st.gps
    local rows=gps_rows(st)
    st._rows=rows
    if not g then
      ui.text(x+1,y+3,"GPS state not loaded. Press R.",colors.gray,colors.black)
    else
      local ready=g.gps_ready==true
      ui.text(x+1,y+1,("GPS %s | hosts %s/%s | clients %s"):format(
        ready and "READY" or "NOT READY",
        tostring(g.hosts_online or 0),tostring(g.minimum_hosts or 4),
        tostring(g.clients_online or 0)
      ),ready and colors.lime or colors.orange,colors.black)

      local yy=y+3
      for i,row in ipairs(rows) do
        if yy>y+h-3 then break end
        local d=row.data
        local selected=i==st.selected
        local bg=selected and colors.lightGray or colors.black
        local online=d.online~=false
        local fg=selected and colors.black or (online and colors.lime or colors.red)
        ui.fill(x,yy,x+w-1,yy,bg,fg)
        local prefix=row.kind=="host" and "H" or "C"
        local coord=(d.x and d.y and d.z) and
          (" %.0f %.0f %.0f"):format(d.x,d.y,d.z) or ""
        local line=("%s %-3s %-21s%s"):format(
          prefix,tostring(d.id or "-"),tostring(d.label or "-"):sub(1,21),coord
        )
        ui.text(x+1,yy,line:sub(1,math.max(1,w-2)),fg,bg)
        yy=yy+1
      end
      ui.text(x+1,y+h-2,"Enter restart selected host | C controller | R refresh",colors.gray,colors.black)
    end

  else
    local l=st.lights
    local rows=light_rows(st)
    st._rows=rows
    if not l then
      ui.text(x+1,y+3,"Lighting state not loaded. Press R.",colors.gray,colors.black)
    else
      ui.text(x+1,y+1,("Lighting %s | relays %s | desired %s"):format(
        l.healthy==false and "FAULT" or "OK",
        tostring(l.relay_count or 0),
        l.desired_on and "ON" or "OFF"
      ),l.healthy==false and colors.red or colors.lime,colors.black)

      for i,room in ipairs(rows) do
        local yy=y+2+i
        if yy>y+h-3 then break end
        local bg=i==st.selected and colors.lightGray or colors.black
        local fg=i==st.selected and colors.black or state_color(room.state,true)
        ui.fill(x,yy,x+w-1,yy,bg,fg)
        local line=("%-22s %-8s %d/%d"):format(
          tostring(room.name or "-"):sub(1,22),
          tostring(room.state or "-"),
          tonumber(room.present or 0),tonumber(room.relay_count or 0)
        )
        ui.text(x+1,yy,line:sub(1,math.max(1,w-2)),fg,bg)
      end
      ui.text(x+1,y+h-2,"Space toggle | A animate | O all on | F all off",colors.gray,colors.black)
    end
  end

  local tone=st.message and (
    tostring(st.message):lower():find("fail",1,true) and "danger"
    or tostring(st.message):lower():find("offline",1,true) and "danger"
    or "accent"
  ) or nil
  Theme.footer(ui,x,y+h-1,w,tostring(st.message or "Tab view"),tone)
end

local function selected_node(st)
  return fleet_rows(st)[st.selected]
end

local function restart_selected_service(st,node)
  if not node then st.message="No node selected";return end
  local role=tostring(node.role or (node.status and node.status.role) or "")
  local service=SERVICE_BY_ROLE[role]
  if not service then
    st.message="No role service mapped for "..role
    return
  end
  local data,err=admin.node(node.id,"service",{service=service,service_action="restart"})
  st.message=data and ("Restarted "..service) or tostring(err)
end

local function reboot_node(st,node)
  if not node then st.message="No node selected";return end
  local data,err=admin.node(node.id,"reboot")
  st.message=data and ("Reboot requested for ID "..tostring(node.id)) or tostring(err)
end

local function restart_gps_target(st,row)
  if not row or row.kind~="host" then st.message="Select a GPS host";return end
  local data,err=admin.node(row.data.id,"service",{
    service="cclua-gps-host.service",service_action="restart"
  })
  st.message=data and ("Restarted GPS host ID "..tostring(row.data.id)) or tostring(err)
end

local function restart_gps_controller(st)
  local id=tonumber(st.gps and st.gps.computer_id) or 14
  local data,err=admin.node(id,"service",{
    service="cclua-gps-control.service",service_action="restart"
  })
  st.message=data and "GPS controller restarted" or tostring(err)
end

local function light_command(st,cmd)
  local data,err=admin.lighting(cmd)
  if not data then st.message=tostring(err);return end
  st.lights=data.state or st.lights
  st.message="Lighting command applied"
end

function M.event(ctx,st,ev,a,b,c,rx,ry,w,h)
  if ev=="key" then
    if a==keys.tab then
      st.tab=st.tab%#tabs+1
      st.selected=1
      st.message="R refresh"
      return true
    elseif a==keys.r then
      refresh(st);return true
    elseif a==keys.up then
      st.selected=math.max(1,st.selected-1);return true
    elseif a==keys.down then
      st.selected=math.min(math.max(1,#(st._rows or {})),st.selected+1);return true
    end

    if st.tab==1 then
      local node=selected_node(st)
      if a==keys.enter then restart_selected_service(st,node);return true end
      if a==keys.b then reboot_node(st,node);return true end

    elseif st.tab==2 then
      local row=(st._rows or {})[st.selected]
      if a==keys.enter then restart_gps_target(st,row);return true end
      if a==keys.c then restart_gps_controller(st);return true end

    else
      local room=light_rows(st)[st.selected]
      if a==keys.space and room then
        local on=tostring(room.state or "")~="ON"
        light_command(st,{op="room_set",room=room.name,value=on});return true
      elseif a==keys.a and room then
        light_command(st,{op="room_animate",room=room.name});return true
      elseif a==keys.o then
        light_command(st,{op="all",value=true});return true
      elseif a==keys.f then
        light_command(st,{op="all",value=false});return true
      end
    end

  elseif ev=="mouse_click" and rx and ry then
    if ry==1 then
      if rx<10 then st.tab=1
      elseif rx<18 then st.tab=2
      else st.tab=3 end
      st.selected=1
      st.message="R refresh"
      return true
    elseif ry>=3 and ry<h-1 then
      local idx=ry-2
      if st.tab==2 then idx=ry-3 end
      if (st._rows or {})[idx] then st.selected=idx;return true end
    end
  end
  return false
end

return M
