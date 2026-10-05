local M={}
local Theme=dofile("/usr/lib/cclua/desktop/theme.lua")
local theater=dofile("/usr/lib/cclua/theater.lua")

local tabs={"Playback","Movies","Lights","Hardware"}

local function safe_catalog()
  local ok,value,err=pcall(theater.catalog)
  if ok and type(value)=="table" then return value,nil end
  return {},ok and err or tostring(value)
end

local function clamp(v,lo,hi)
  v=tonumber(v) or lo
  if v<lo then return lo end
  if v>hi then return hi end
  return v
end

local function fit(s,n)
  return Theme.fit(tostring(s or ""),n)
end

function M.new(ctx,opts)
  local movies,err=safe_catalog()
  return {
    title="Theater",icon="Th",
    tab=1,movies=movies,selected=1,scroll=1,
    message=err and ("Bridge: "..tostring(err)) or nil,
    messageTone=err and "warning" or nil,
  }
end

function M.get_title(st)
  local state=theater.state()
  if state and state.state=="PLAYING" and state.title then
    return fit(state.title,22).." - Theater"
  end
  return "Theater"
end

local function refresh(st)
  local movies,err=safe_catalog()
  st.movies=movies
  st.selected=math.max(1,math.min(math.max(1,#movies),st.selected or 1))
  if err then
    st.message="Movie bridge: "..tostring(err)
    st.messageTone="warning"
  else
    st.message=("Library refreshed: %d movie(s)"):format(#movies)
    st.messageTone="success"
  end
end

local function progress(ui,x,y,w,pct)
  local inner=math.max(1,w-2)
  local fill=math.floor(inner*clamp(pct,0,1)+0.5)
  ui.fill(x,y,x+w-1,y,Theme.c.surface,Theme.c.text)
  if fill>0 then ui.fill(x+1,y,x+fill,y,Theme.c.accent,Theme.c.text) end
end

local function button(ui,x,y,w,label,active,tone)
  local bg=active and Theme.c.selected_bg or Theme.c.surface
  local fg=active and Theme.c.selected_fg or Theme.c.text
  if not active then
    if tone=="success" then fg=Theme.c.success
    elseif tone=="warning" then fg=Theme.c.warning
    elseif tone=="danger" then fg=Theme.c.danger
    elseif tone=="accent" then fg=Theme.c.accent_alt end
  end
  ui.fill(x,y,x+w-1,y,bg,fg)
  ui.center(y,fit(label,w),fg,bg,x,x+w-1)
end

local function draw_playback(st,ui,x,y,w,h,state)
  local title=state.title or "No movie loaded"
  Theme.section(ui,x+1,y+1,w-2,"Now Playing")
  ui.text(x+1,y+2,fit(title,w-2),state.title and Theme.c.text or Theme.c.muted,Theme.c.bg)

  local pos=tonumber(state.position) or 0
  local dur=tonumber(state.duration) or 0
  local pct=dur>0 and pos/dur or 0
  progress(ui,x+1,y+4,w-2,pct)
  local timing=theater.format_time(pos).." / "..theater.format_time(dur)
  ui.text(x+1,y+5,timing,Theme.c.muted,Theme.c.bg)

  local status=tostring(state.state or "IDLE")
  Theme.kv(ui,x+1,y+7,w-2,"State",status,status)
  Theme.kv(ui,x+1,y+8,w-2,"Volume",("%d%%"):format(math.floor((tonumber(state.volume) or 0)*100+0.5)))
  Theme.kv(ui,x+1,y+9,w-2,"Lights",
    ("%s  %d%%"):format(tostring(state.scene or "house"),tonumber(state.brightness) or 0))
  Theme.kv(ui,x+1,y+10,w-2,"Dropped",tostring(state.dropped_frames or 0))

  if h>=17 then
    local gap=1
    local bw=math.max(8,math.floor((w-2-gap*3)/4))
    local by=y+12
    button(ui,x+1,by,bw,"-10s",false)
    button(ui,x+1+bw+gap,by,bw,status=="PLAYING" and "Pause" or "Play",true)
    button(ui,x+1+(bw+gap)*2,by,bw,"+10s",false)
    button(ui,x+1+(bw+gap)*3,by,bw,"Stop",false,"danger")
    ui.text(x+1,by+2,"Space Play/Pause   Left/Right Seek   +/- Volume",Theme.c.dim,Theme.c.bg)
  end
end

local function draw_movies(st,ui,x,y,w,h,state)
  Theme.section(ui,x+1,y+1,w-2,"Movie Library")
  if #st.movies==0 then
    ui.text(x+1,y+3,"No movies found.",Theme.c.warning,Theme.c.bg)
    ui.text(x+1,y+4,"Drop MP4/MKV/WebM files into the theater Movies folder.",Theme.c.muted,Theme.c.bg)
    ui.text(x+1,y+6,"R  Refresh library",Theme.c.accent_alt,Theme.c.bg)
    return
  end

  local rows=math.max(1,h-5)
  if st.selected<st.scroll then st.scroll=st.selected end
  if st.selected>=st.scroll+rows then st.scroll=st.selected-rows+1 end
  st.scroll=math.max(1,st.scroll)

  local yy=y+2
  for idx=st.scroll,math.min(#st.movies,st.scroll+rows-1) do
    local movie=st.movies[idx]
    local dur=movie.duration and theater.format_time(movie.duration) or "--:--"
    local marker=tostring(state.movie_id)==tostring(movie.id) and "*" or " "
    local row=("%s %-*s %8s"):format(marker,math.max(8,w-14),fit(movie.title,math.max(8,w-14)),dur)
    Theme.list_row(ui,x,yy,w,row,idx==st.selected,
      tostring(state.movie_id)==tostring(movie.id) and "success" or nil)
    yy=yy+1
  end
  ui.text(x+1,y+h-2,"Enter Play   Up/Down Select   R Refresh",Theme.c.dim,Theme.c.bg)
end
local function draw_lights(st,ui,x,y,w,h,state)
  Theme.section(ui,x+1,y+1,w-2,"Cinema Lighting")
  ui.text(x+1,y+2,
    ("Current: %s  |  %d%%  |  %s fixtures"):format(
      tostring(state.scene or "house"),
      tonumber(state.brightness) or 0,
      tostring(state.lights_on or "?")
    ),Theme.c.text,Theme.c.bg)

  local labels={
    {"house","House","100%","Full cleaning / audience entry"},
    {"preshow","Pre-show","60%","Comfortable seating light"},
    {"trailers","Trailers","30%","Low house light"},
    {"feature","Feature","9%","Movie level / guide light"},
    {"blackout","Blackout","0%","All theater fixtures off"},
  }
  local yy=y+4
  for i,row in ipairs(labels) do
    if yy>y+h-3 then break end
    local selected=tostring(state.scene)==row[1]
    local text=("%-10s %4s  %s"):format(row[2],row[3],row[4])
    Theme.list_row(ui,x,yy,w,text,selected,selected and nil or "muted")
    yy=yy+1
  end
  if yy<=y+h-2 then
    ui.text(x+1,yy+1,"1 House  2 Pre-show  3 Trailers  4 Feature  5 Blackout",Theme.c.dim,Theme.c.bg)
  end
end

local function bool_word(v)
  return v and "READY" or "MISSING"
end

local function draw_hardware(st,ui,x,y,w,h,state)
  Theme.section(ui,x+1,y+1,w-2,"Theater Hardware")
  local hw=type(state.hardware)=="table" and state.hardware or {}
  local yy=y+3

  local rows={
    {"Main screen",bool_word(hw.main_present),hw.main_present and "ONLINE" or "FAILED"},
    {"Booth transport",bool_word(hw.transport_present),hw.transport_present and "ONLINE" or "FAILED"},
    {"Booth control",bool_word(hw.control_present),hw.control_present and "ONLINE" or "FAILED"},
    {"Room speakers",("%s / %s"):format(hw.speakers_present or 0,hw.speakers_expected or 22),
      tonumber(hw.speakers_present or 0)>=tonumber(hw.speakers_expected or 22) and "ONLINE" or "DEGRADED"},
    {"Light relays",("%s / %s"):format(hw.relays_present or 0,hw.relays_expected or 55),
      tonumber(hw.relays_present or 0)>=tonumber(hw.relays_expected or 55) and "ONLINE" or "DEGRADED"},
    {"Movie bridge",tostring(state.bridge or "CHECKING"),
      state.bridge=="ONLINE" and "ONLINE" or "DEGRADED"},
    {"Library",tostring(state.catalog_count or #st.movies).." movies",""},
  }
  for _,row in ipairs(rows) do
    if yy>y+h-2 then break end
    Theme.kv(ui,x+1,yy,w-2,row[1],row[2],row[3])
    yy=yy+1
  end

  if hw.main_size and yy<=y+h-2 then
    Theme.kv(ui,x+1,yy,w-2,"Wall size",
      ("%sx%s chars"):format(tostring(hw.main_size[1]),tostring(hw.main_size[2])))
  end
end

function M.draw(ctx,st,ui,x,y,w,h,active)
  ui.fill(x,y,x+w-1,y+h-1,Theme.c.bg,Theme.c.text)
  local state=theater.state()
  local bridge=tostring(state.bridge or "CHECKING")
  Theme.header(ui,x,y,w,"CCLUA Cinema",bridge)

  Theme.tabs(ui,x,y+1,w,tabs,st.tab)
  local bodyY=y+2
  local bodyH=math.max(1,h-3)

  if st.tab==1 then draw_playback(st,ui,x,bodyY,w,bodyH,state)
  elseif st.tab==2 then draw_movies(st,ui,x,bodyY,w,bodyH,state)
  elseif st.tab==3 then draw_lights(st,ui,x,bodyY,w,bodyH,state)
  else draw_hardware(st,ui,x,bodyY,w,bodyH,state) end

  local footer=st.message
    or ("Tab switch view | Scene "..tostring(state.scene or "house")..
      " | "..tostring(state.state or "IDLE"))
  Theme.footer(ui,x,y+h-1,w,footer,st.messageTone)
end
local function set_scene_index(index)
  local scene=theater.scenes[index]
  if scene then theater.scene(scene.id);return true end
  return false
end

local function play_selected(st)
  local movie=st.movies[st.selected]
  if not movie then
    st.message="No movie selected";st.messageTone="warning";return true
  end
  theater.play(movie.id)
  st.message="Starting "..tostring(movie.title)
  st.messageTone="success"
  return true
end

function M.event(ctx,st,ev,a,b,c,rx,ry,w,h)
  if ev=="key" then
    if a==keys.tab then
      st.tab=st.tab%#tabs+1
      st.message=nil;st.messageTone=nil
      return true
    end

    if a==keys.r then refresh(st);theater.command("refresh",{});return true end

    if st.tab==1 then
      if a==keys.space or a==keys.enter then theater.command("toggle",{});return true
      elseif a==keys.left then theater.seek(-10);return true
      elseif a==keys.right then theater.seek(10);return true
      elseif a==keys.up then theater.volume_delta(0.05);return true
      elseif a==keys.down then theater.volume_delta(-0.05);return true
      elseif a==keys.s then theater.stop();return true
      end
    elseif st.tab==2 then
      if a==keys.up then st.selected=math.max(1,st.selected-1);return true
      elseif a==keys.down then st.selected=math.min(math.max(1,#st.movies),st.selected+1);return true
      elseif a==keys.enter or a==keys.space then return play_selected(st)
      end
    elseif st.tab==3 then
      if a==keys.one then return set_scene_index(1)
      elseif a==keys.two then return set_scene_index(2)
      elseif a==keys.three then return set_scene_index(3)
      elseif a==keys.four then return set_scene_index(4)
      elseif a==keys.five then return set_scene_index(5)
      elseif a==keys.up then
        local state=theater.state()
        theater.command("brightness",{value=math.min(100,(tonumber(state.brightness) or 0)+10)})
        return true
      elseif a==keys.down then
        local state=theater.state()
        theater.command("brightness",{value=math.max(0,(tonumber(state.brightness) or 0)-10)})
        return true
      end
    end
  elseif ev=="mouse_scroll" then
    if st.tab==2 then
      st.selected=math.max(1,math.min(math.max(1,#st.movies),st.selected+(tonumber(a) or 0)))
      return true
    end
  elseif ev=="mouse_click" and rx and ry then
    if ry==2 then
      local tx=1
      for i,label in ipairs(tabs) do
        local width=#label+3
        if rx>=tx and rx<tx+width then st.tab=i;return true end
        tx=tx+width+1
      end
    end

    local bodyRow=ry-2
    if st.tab==1 and bodyRow>=12 and bodyRow<=14 then
      local quarter=math.max(1,math.floor(w/4))
      if rx<=quarter then theater.seek(-10)
      elseif rx<=quarter*2 then theater.command("toggle",{})
      elseif rx<=quarter*3 then theater.seek(10)
      else theater.stop() end
      return true
    elseif st.tab==2 and bodyRow>=3 and bodyRow<=h-3 then
      local rows=math.max(1,h-6)
      local idx=st.scroll+(bodyRow-3)
      if idx>=1 and idx<=#st.movies then
        if st.selected==idx then
          return play_selected(st)
        end
        st.selected=idx
        return true
      end
    elseif st.tab==3 and bodyRow>=5 and bodyRow<=9 then
      return set_scene_index(bodyRow-4)
    end
  end
  return false
end

return M
