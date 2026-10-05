return function(ctx)
  local config=dofile("/usr/lib/cclua/config.lua")
  local monitorLayout=dofile("/usr/lib/cclua/monitor_layout.lua")
  local machine=config.machine()

  local STATE_PATH="/var/lib/cclua/theater-state.json"
  local BRIDGE=tostring(machine.theater_bridge_base or "http://127.0.0.1:8766/v1")
  local ORIGIN=BRIDGE:gsub("/v1/?$","")
  local mainName=tostring(machine.theater_main_monitor or "monitor_7")
  local transportName=tostring(machine.theater_transport_monitor or "left")
  local controlName=tostring(machine.theater_control_monitor or "right")
  local boothSpeaker=tostring(machine.theater_booth_speaker or "bottom")
  local fps=math.max(2,math.min(20,tonumber(machine.theater_video_fps) or 20))
  local targetCols=tonumber(machine.theater_video_cols) or 0
  local targetRows=tonumber(machine.theater_video_rows) or 0
  local speakerOutputVolume=math.max(0.1,math.min(3.0,tonumber(machine.theater_speaker_output_volume) or 3.0))
  local segmentSeconds=math.max(0.25,math.min(2,tonumber(machine.theater_segment_seconds) or 0.5))
  local segmentPrefetch=math.max(1,math.min(3,tonumber(machine.theater_segment_prefetch) or 2))
  local initialBufferSegments=math.max(1,math.min(segmentPrefetch,
    tonumber(machine.theater_initial_buffer_segments) or 2))

  local scenes={
    house={label="HOUSE",level=100},
    preshow={label="PRE-SHOW",level=60},
    trailers={label="TRAILERS",level=30},
    feature={label="FEATURE",level=9},
    blackout={label="BLACKOUT",level=0},
  }
  local sceneOrder={"house","preshow","trailers","feature","blackout"}

  -- Physical mapping discovered from the theater build. Each relay's BOTTOM
  -- output directly feeds one ceiling fixture. IDs are wired-peripheral IDs.
  local fixtureIds={
    {74,75,76,77,78,79,80,81,82,120,119},
    {91,90,89,88,87,86,85,84,83,121,122},
    {92,93,94,95,96,97,98,99,100,123,124},
    {109,108,107,106,105,104,103,102,101,125,126},
    {110,111,112,113,114,116,115,117,118,127,128},
  }
  local fixtures={}
  for xi,row in ipairs(fixtureIds) do
    for zi,id in ipairs(row) do
      fixtures[#fixtures+1]={
        id=id,name="redstone_relay_"..id,
        x=33+(xi-1)*3,z=-10+(zi-1)*2,
        xi=xi,zi=zi,
      }
    end
  end

  -- The theater is a 5 x 11 ceiling grid. Keep a coordinate lookup and
  -- dim it in symmetric cinema zones instead of pseudo-random spatial dither.
  -- z-index 1 is nearest the screen, z-index 11 is nearest the booth/rear.
  local fixtureByGrid={}
  for _,f in ipairs(fixtures) do fixtureByGrid[f.xi..":"..f.zi]=f end

  local fixtureGroups={}
  local function group(...)
    local g={}
    for _,key in ipairs({...}) do
      local f=fixtureByGrid[key]
      if f then g[#g+1]=f end
    end
    if #g>0 then fixtureGroups[#fixtureGroups+1]=g end
  end

  -- Five low-level guide fixtures: rear center plus two mirrored edge pairs.
  group("3:11")
  group("1:11","5:11")
  group("1:9","5:9")

  -- Complete the outer aisle/perimeter pair-by-pair, rear toward screen.
  for _,zi in ipairs({10,8,7,6,5,4,3,2,1}) do
    group("1:"..zi,"5:"..zi)
  end

  -- Add the inner mirrored columns from rear toward the screen.
  for zi=11,1,-1 do group("2:"..zi,"4:"..zi) end

  -- Fill the remaining centerline last, rear toward the screen.
  for zi=10,1,-1 do group("3:"..zi) end

  local COMMAND_PATH="/var/lib/cclua/theater-command.json"
  local state=config.read_json(STATE_PATH,{}) or {}
  local persistedState=tostring(state.state or "IDLE")
  state.schema=2
  state.state="IDLE"
  state.scene=tostring(state.scene or "house")
  -- A reboot/crash during feature playback must never strand the room dark.
  if (persistedState=="PLAYING" or persistedState=="BUFFERING")
    and (state.scene=="feature" or state.scene=="blackout") then
    state.scene="house"
  end
  if not scenes[state.scene] then state.scene="house" end
  state.brightness=tonumber(state.brightness) or scenes[state.scene].level
  state.volume=math.max(0,math.min(1,tonumber(state.volume) or 0.85))
  state.position=0
  state.movie_id=nil
  state.title=nil
  state.duration=nil
  state.error=nil
  state.hardware={}
  state.catalog_count=0
  state.selected_index=tonumber(state.selected_index) or 1
  state.video_fps=fps

  local catalog={}
  local catalogUrl=BRIDGE.."/catalog"
  local catalogInflight=false
  local session=nil
  local sessionSeq=0
  local fixtureOn={}
  local lightAnimation=nil
  local lastRenderKey={}
  local monitorCache={}
  local mainDefaultPalette=nil
  local activeMainPalette=nil

  local function now_ms()
    return os.epoch and os.epoch("utc") or math.floor(os.clock()*1000)
  end

  local function clamp(v,lo,hi)
    v=tonumber(v) or lo
    if v<lo then return lo end
    if v>hi then return hi end
    return v
  end

  local function apply_catalog(data)
    if type(data)~="table" then return nil,"invalid bridge JSON" end
    catalog=type(data.movies)=="table" and data.movies or {}
    config.write_json("/var/lib/cclua/theater-catalog.json",{
      schema=1,updated_at=now_ms(),movies=catalog,
    })
    state.catalog_count=#catalog
    state.bridge="ONLINE"
    state.bridge_error=nil
    state.selected_index=math.max(1,math.min(math.max(1,#catalog),state.selected_index or 1))
    return catalog
  end

  local function load_cached_catalog()
    local cached=config.read_json("/var/lib/cclua/theater-catalog.json",nil)
    if type(cached)=="table" and type(cached.movies)=="table" then
      catalog=cached.movies
      state.catalog_count=#catalog
      state.selected_index=math.max(1,math.min(math.max(1,#catalog),state.selected_index or 1))
    end
  end

  local function refresh_catalog()
    if #catalog==0 then load_cached_catalog() end
    if catalogInflight then return catalog end
    if not http or not http.request then
      state.bridge="OFFLINE"
      state.bridge_error="HTTP API unavailable"
      return catalog,state.bridge_error
    end
    local ok,err=http.request{
      url=catalogUrl,method="GET",
      headers={["Accept"]="application/json",["User-Agent"]="CCLUA-Theater/0.3"},
      binary=false,timeout=5,
    }
    if ok then
      catalogInflight=true
      if state.bridge~="ONLINE" then state.bridge="CHECKING" end
      return catalog
    end
    state.bridge="OFFLINE"
    state.bridge_error=tostring(err or "HTTP request failed")
    return catalog,state.bridge_error
  end

  local function find_movie(id)
    id=tostring(id or "")
    for i,item in ipairs(catalog) do
      if tostring(item.id)==id then return item,i end
    end
    refresh_catalog()
    for i,item in ipairs(catalog) do
      if tostring(item.id)==id then return item,i end
    end
    return nil
  end

  local function save_state()
    state.updated_at=now_ms()
    local clean={}
    for k,v in pairs(state) do clean[k]=v end
    clean.hardware=state.hardware
    config.write_json(STATE_PATH,clean)
  end

  local function peripheral_ok(name,ptype)
    return name and peripheral.hasType(name,ptype)
  end

  local function wrap_monitor(name)
    if not peripheral_ok(name,"monitor") then
      monitorCache[name]=nil
      return nil
    end
    local m=monitorCache[name]
    if not m then
      m=peripheral.wrap(name)
      monitorCache[name]=m
    end
    return m
  end
  local function capture_main_palette(mon)
    if mainDefaultPalette or not mon or not mon.getPaletteColor then return end
    local palette={}
    for i=0,15 do
      local ok,r,g,b=pcall(mon.getPaletteColor,2^i)
      if not ok then return end
      palette[i+1]={r,g,b}
    end
    mainDefaultPalette=palette
  end

  local function restore_main_palette()
    if not mainDefaultPalette then return end
    local mon=wrap_monitor(mainName)
    if not mon or not mon.setPaletteColor then return end
    if activeMainPalette==nil then return end
    for i,rgb in ipairs(mainDefaultPalette) do
      pcall(mon.setPaletteColor,2^(i-1),rgb[1],rgb[2],rgb[3])
    end
    activeMainPalette=nil
  end

  local function apply_main_palette(mon,palette,key)
    if not mon or not mon.setPaletteColor or type(palette)~="table" or #palette~=16 then
      return false
    end
    key=tostring(key or "")
    if activeMainPalette==key and key~="" then return true end
    for i,rgb in ipairs(palette) do
      pcall(mon.setPaletteColor,2^(i-1),
        clamp((rgb[1] or 0)/255,0,1),
        clamp((rgb[2] or 0)/255,0,1),
        clamp((rgb[3] or 0)/255,0,1))
    end
    activeMainPalette=key~="" and key or true
    return true
  end

  -- Full theater array. CCPerf releases identical PCM blocks as one
  -- synchronized group, so all room speakers share the same sample epoch.
  local speakerOrder={
    7,2,8,15,20,18,0,1,
    6,5,4,3,9,10,11,12,13,14,16,17,19,21,
  }
  local expectedRoomSpeakers=#speakerOrder
  local function room_speakers()
    local out={}
    for _,id in ipairs(speakerOrder) do
      local name="speaker_"..id
      if name~=boothSpeaker and peripheral_ok(name,"speaker") then
        out[#out+1]={name=name,obj=peripheral.wrap(name),id=id}
      end
    end
    return out
  end

  local function hardware_snapshot()
    local main=wrap_monitor(mainName)
    local north=wrap_monitor(transportName)
    local south=wrap_monitor(controlName)
    local mw,mh=nil,nil
    local mainScale=nil
    if main then
      mw,mh=main.getSize()
      if main.getTextScale then
        local okScale,value=pcall(main.getTextScale)
        if okScale then mainScale=tonumber(value) end
      end
    end
    local tw,th=nil,nil
    if north then tw,th=north.getSize() end
    local cw,ch=nil,nil
    if south then cw,ch=south.getSize() end

    local relays=0
    for _,f in ipairs(fixtures) do
      if peripheral_ok(f.name,"redstone_relay") then relays=relays+1 end
    end
    local speakers=#room_speakers()
    state.hardware={
      main_monitor=mainName,main_present=main~=nil,main_size=main and {mw,mh} or nil,
      main_text_scale=mainScale,
      transport_monitor=transportName,transport_present=north~=nil,transport_size=north and {tw,th} or nil,
      control_monitor=controlName,control_present=south~=nil,control_size=south and {cw,ch} or nil,
      speakers_present=speakers,speakers_expected=expectedRoomSpeakers,
      speaker_output_volume=speakerOutputVolume,
      relays_present=relays,relays_expected=#fixtures,
      booth_speaker=boothSpeaker,booth_speaker_present=peripheral_ok(boothSpeaker,"speaker"),
    }
  end

  local function relay_set(f,on)
    if not peripheral_ok(f.name,"redstone_relay") then
      fixtureOn[f.id]=false
      return nil,"missing "..f.name
    end
    local relay=peripheral.wrap(f.name)
    local ok,err=pcall(relay.setOutput,"bottom",on==true)
    if ok then fixtureOn[f.id]=on==true;return true end
    return nil,tostring(err)
  end

  local function target_fixture_set(level)
    level=clamp(level,0,100)
    local target=#fixtures*level/100
    local cumulative=0
    local bestGroups=0
    local bestDiff=math.abs(target)

    -- Only stop at complete symmetric group boundaries. This means a custom
    -- slider may land one fixture above/below its mathematical target, but a
    -- mirrored pair is never split just to hit an exact integer count.
    for i,g in ipairs(fixtureGroups) do
      cumulative=cumulative+#g
      local diff=math.abs(cumulative-target)
      if diff<=bestDiff then
        bestDiff=diff
        bestGroups=i
      end
    end

    if level>=100 then bestGroups=#fixtureGroups end
    if level<=0 then bestGroups=0 end

    local wanted={}
    local count=0
    for i=1,bestGroups do
      for _,f in ipairs(fixtureGroups[i]) do
        wanted[f.id]=true
        count=count+1
      end
    end
    return wanted,count
  end

  local function finish_light_animation(anim)
    state.brightness=anim.level
    state.lights_on=anim.target_count
    state.light_errors=anim.errors or 0
    state.lighting_transition=false
    state.target_brightness=nil
    lightAnimation=nil
    save_state()
  end

  local function step_light_animation()
    local anim=lightAnimation
    if not anim then return false end
    local stop=math.min(#anim.changes,anim.index+anim.batch-1)
    for i=anim.index,stop do
      local item=anim.changes[i]
      local ok=relay_set(item.fixture,item.value)
      if not ok then anim.errors=(anim.errors or 0)+1 end
    end
    anim.index=stop+1
    if anim.index>#anim.changes then
      finish_light_animation(anim)
      return true
    end
    anim.timer=os.startTimer(0.05)
    return true
  end

  local function set_brightness(level,animate)
    level=clamp(level,0,100)
    local wanted,targetCount=target_fixture_set(level)
    local changes={}
    for _,f in ipairs(fixtures) do
      local desired=wanted[f.id]==true
      local current=fixtureOn[f.id]==true
      if desired~=current then changes[#changes+1]={fixture=f,value=desired} end
    end

    if lightAnimation and lightAnimation.timer and os.cancelTimer then
      pcall(os.cancelTimer,lightAnimation.timer)
    end
    lightAnimation=nil

    if animate==false or #changes==0 then
      local errors=0
      for _,item in ipairs(changes) do
        local ok=relay_set(item.fixture,item.value)
        if not ok then errors=errors+1 end
      end
      finish_light_animation({
        level=level,target_count=targetCount,errors=errors,changes={},index=1,batch=1
      })
      return errors==0
    end

    -- Redstone lamps are binary. Perceived dimming is achieved by changing an
    -- evenly distributed subset of fixtures in four-lamp batches every 50 ms.
    -- No fixture is PWM-flickered, and theaterd remains responsive while fading.
    lightAnimation={
      level=level,target_count=targetCount,errors=0,
      changes=changes,index=1,batch=4,timer=nil
    }
    state.lighting_transition=true
    state.target_brightness=level
    step_light_animation()
    save_state()
    return true
  end

  local function set_scene(name,animate)
    name=tostring(name or ""):lower()
    local scene=scenes[name]
    if not scene then return nil,"unknown scene" end
    state.scene=name
    state.state=state.state=="ERROR" and "IDLE" or state.state
    set_brightness(scene.level,animate)
    save_state()
    return true
  end

  local function configure_monitors()
    local main=wrap_monitor(mainName)
    if main then
      capture_main_palette(main)
      monitorLayout.fit(main,{
        min_width=144,min_height=54,
        fixed_scale=tonumber(machine.theater_main_text_scale) or 1.5,
      })
      pcall(main.setCursorBlink,false)
      pcall(main.setBackgroundColor,colors.black)
      pcall(main.setTextColor,colors.white)
    end

    for _,name in ipairs({transportName,controlName}) do
      local mon=wrap_monitor(name)
      if mon then
        monitorLayout.fit(mon,{min_width=38,min_height=18,max_scale=2.0,auto_max_scale=1.0})
        pcall(mon.setCursorBlink,false)
        pcall(mon.setBackgroundColor,colors.black)
        pcall(mon.setTextColor,colors.white)
      end
    end
  end

  local function fit(s,n)
    s=tostring(s or "")
    if n<=0 then return "" end
    if #s<=n then return s end
    if n<=1 then return "~" end
    return s:sub(1,n-1).."~"
  end

  local function line(mon,y,text,fg,bg)
    if not mon then return end
    local w,h=mon.getSize()
    if y<1 or y>h then return end
    text=fit(text,w)
    mon.setCursorPos(1,y)
    mon.setBackgroundColor(bg or colors.black)
    mon.setTextColor(fg or colors.white)
    mon.write(text..string.rep(" ",math.max(0,w-#text)))
  end

  local function progress_bar(mon,y,pct,label)
    local w,h=mon.getSize()
    if y<1 or y>h then return end
    local inner=math.max(5,w-4)
    local fill=math.floor(inner*clamp(pct,0,1)+0.5)
    mon.setCursorPos(2,y)
    mon.setBackgroundColor(colors.gray)
    mon.write(string.rep(" ",inner))
    if fill>0 then
      mon.setCursorPos(2,y)
      mon.setBackgroundColor(colors.orange)
      mon.write(string.rep(" ",fill))
    end
    if label then
      local txt=fit(label,inner)
      local x=2+math.max(0,math.floor((inner-#txt)/2))
      mon.setCursorPos(x,y)
      mon.setTextColor(colors.white)
      mon.setBackgroundColor(colors.black)
      mon.write(txt)
    end
    mon.setBackgroundColor(colors.black)
  end

  local function fmt_time(v)
    v=math.max(0,math.floor(tonumber(v) or 0))
    local h=math.floor(v/3600)
    local m=math.floor((v%3600)/60)
    local s=v%60
    return h>0 and ("%d:%02d:%02d"):format(h,m,s) or ("%d:%02d"):format(m,s)
  end
  local function current_position()
    if session and session.active and session.go and session.start_epoch then
      return math.max(0,(session.start_position or 0)+(now_ms()-session.start_epoch)/1000)
    end
    return tonumber(state.position) or 0
  end

  local function render_transport()
    local mon=wrap_monitor(transportName)
    if not mon then return end
    local w,h=mon.getSize()
    mon.setBackgroundColor(colors.black);mon.clear()
    line(mon,1," CCLUA CINEMA // TRANSPORT",colors.white,colors.blue)

    local title=state.title or "No feature loaded"
    line(mon,3,fit(title,w-2),state.movie_id and colors.white or colors.gray)
    local pos=current_position()
    local dur=tonumber(state.duration) or 0
    local pct=dur>0 and math.min(1,pos/dur) or 0
    progress_bar(mon,5,pct,fmt_time(pos).." / "..fmt_time(dur))

    line(mon,7,("STATE  %-10s  VOL %3d%%"):format(
      tostring(state.state or "IDLE"),math.floor((state.volume or 0)*100+0.5)
    ),state.state=="PLAYING" and colors.lime or state.state=="ERROR" and colors.red or colors.lightGray)
    line(mon,8,("LIGHT  %-10s  %3d%%"):format(
      tostring((scenes[state.scene] or {}).label or state.scene),tonumber(state.brightness) or 0
    ),colors.yellow)
    if h>=11 then
      line(mon,h-2," << -10s    PLAY/PAUSE    +10s >>",colors.cyan)
      line(mon,h-1," Touch L / CENTER / R for transport",colors.gray)
    end
    line(mon,h,("AUDIO %d/%d  SCREEN %s"):format(
      tonumber((state.hardware or {}).speakers_present) or 0,expectedRoomSpeakers,
      (state.hardware or {}).main_present and "READY" or "MISSING"
    ),(state.hardware or {}).main_present and colors.lime or colors.red)
  end

  local function render_control()
    local mon=wrap_monitor(controlName)
    if not mon then return end
    local w,h=mon.getSize()
    mon.setBackgroundColor(colors.black);mon.clear()
    line(mon,1," CCLUA CINEMA // HOUSE CONTROL",colors.white,colors.blue)
    line(mon,2,("Scene %-9s | %d fixtures | Bridge %s"):format(
      tostring((scenes[state.scene] or {}).label or state.scene),
      tonumber(state.lights_on) or 0,tostring(state.bridge or "CHECKING")
    ),state.bridge=="ONLINE" and colors.lime or colors.orange)

    local labels={"HOUSE 100%","PRE-SHOW 60%","TRAILERS 30%","FEATURE 9%","BLACKOUT"}
    local maxScenes=math.min(#labels,math.max(0,h-8))
    for i=1,maxScenes do
      local sceneId=sceneOrder[i]
      local selected=state.scene==sceneId
      line(mon,3+i,(selected and "> " or "  ")..labels[i],
        selected and colors.black or colors.white,
        selected and colors.yellow or colors.black)
    end

    local y=4+maxScenes+1
    if y<=h-3 then line(mon,y,"MOVIES",colors.cyan);y=y+1 end
    local start=math.max(1,math.min(#catalog,tonumber(state.selected_index) or 1)-1)
    while y<=h-2 and start<=#catalog do
      local item=catalog[start]
      local selected=start==(tonumber(state.selected_index) or 1)
      line(mon,y,(selected and "> " or "  ")..fit(item.title,w-3),
        selected and colors.black or colors.lightGray,
        selected and colors.lightGray or colors.black)
      y=y+1;start=start+1
    end
    line(mon,h,"Touch scene/movie | Desktop for full control",colors.gray)
  end

  local function render_main_idle()
    if session and session.active and state.state=="PLAYING" then return end
    restore_main_palette()
    local mon=wrap_monitor(mainName)
    if not mon then return end
    local key=table.concat({
      tostring(state.state),tostring(state.title),tostring(state.position),
      tostring(state.bridge),tostring(state.scene)
    },"|")
    if lastRenderKey.main==key then return end
    lastRenderKey.main=key
    local w,h=mon.getSize()
    mon.setBackgroundColor(colors.black);mon.setTextColor(colors.white);mon.clear()

    local title=state.title or "CCLUA CINEMA"
    local subtitle
    if state.state=="PAUSED" then
      subtitle="PAUSED  "..fmt_time(state.position).." / "..fmt_time(state.duration)
    elseif state.state=="ERROR" then
      subtitle="SYSTEM ERROR  "..tostring(state.error or "")
    elseif #catalog==0 then
      subtitle="THEATER READY // NO MOVIES IN LIBRARY"
    else
      subtitle=("%d FEATURES AVAILABLE // HOUSE %s"):format(#catalog,
        tostring((scenes[state.scene] or {}).label or state.scene))
    end
    local y=math.max(2,math.floor(h/2)-1)
    local x=math.max(1,math.floor((w-#title)/2)+1)
    mon.setCursorPos(x,y);mon.setTextColor(colors.orange);mon.write(fit(title,w))
    local sub=fit(subtitle,w-4)
    mon.setCursorPos(math.max(1,math.floor((w-#sub)/2)+1),math.min(h,y+2))
    mon.setTextColor(state.state=="ERROR" and colors.red or colors.lightGray);mon.write(sub)
  end

  local function render_all()
    local ok,err=pcall(function()
      render_transport()
      render_control()
      render_main_idle()
    end)
    if not ok then
      ctx.kernel.log.write("warning","theaterd","display render failed",{error=tostring(err)},ctx.process.pid)
      monitorCache={}
    end
  end
  local function read_exact(h,n)
    local parts={}
    local total=0
    while total<n do
      local chunk=h.read(n-total)
      if not chunk then break end
      parts[#parts+1]=chunk
      total=total+#chunk
    end
    if total~=n then return nil,total end
    return table.concat(parts)
  end

  local function pcm_decode(raw,gain)
    gain=clamp(gain==nil and 1 or gain,0,1)
    local out={}
    for i=1,#raw do
      local b=string.byte(raw,i)
      local sample=b>=128 and b-256 or b
      sample=math.floor(sample*gain+(sample>=0 and 0.5 or -0.5))
      out[i]=math.max(-128,math.min(127,sample))
    end
    return out
  end

  local function stop_process(pid)
    if not pid then return end
    local proc=ctx.kernel.process.get(pid)
    if proc and proc.state~="exited" and proc.state~="killed" and proc.state~="crashed" then
      ctx.kernel.process.exit(proc,143,"killed")
      if os.queueEvent then os.queueEvent("cclua_process_exit",proc.pid,143,"killed") end
    end
  end

  local function stop_session(keepPosition)
    if not session then return end
    if keepPosition then state.position=current_position() end
    session.active=false
    stop_process(session.av_pid)
    stop_process(session.audio_pid)
    stop_process(session.video_pid)
    for _,s in ipairs(room_speakers()) do pcall(s.obj.stop) end
    session=nil
  end

  local function open_stream(s,kind,url,headers)
    local lastErr=nil
    for attempt=1,6 do
      if not s.active then return nil,"session stopped" end
      s[kind.."_stage"]="connecting"
      s[kind.."_attempt"]=attempt
      local h,err=http.get(url,headers,true)
      if h then
        s[kind.."_last_error"]=nil
        return h
      end
      lastErr=tostring(err or "Could not connect")
      s[kind.."_last_error"]=lastErr
      s[kind.."_stage"]="retry "..attempt
      if attempt<6 then
        coroutine.yield("sleep",now_ms()+math.min(1200,150*attempt))
      end
    end
    return nil,lastErr or "Could not connect"
  end

  local function wait_sync(s,kind)
    if not s.active then return false end
    s[kind.."_ready"]=true
    s[kind.."_stage"]="ready"
    s[kind.."_ready_at"]=now_ms()

    -- The audio/video workers share the same session table. Use that as the
    -- synchronization barrier instead of depending on custom queued events,
    -- which may be consumed by another coroutine while native HTTP APIs yield.
    local waitStarted=now_ms()
    while s.active and not (s.audio_ready and s.video_ready) do
      if now_ms()-waitStarted>15000 then
        error(kind.." stream sync timed out waiting for peer",0)
      end
      coroutine.yield("sleep",now_ms()+25)
    end
    if not s.active then return false end

    if not s.start_epoch then
      s.start_epoch=now_ms()+250
      s.go=true
    end
    while s.active and now_ms()<(s.start_epoch or 0) do
      coroutine.yield("sleep",math.min(s.start_epoch,now_ms()+25))
    end
    s[kind.."_stage"]="playing"
    return s.active
  end

  local function spawn_audio(s,movie)
    local speakers=room_speakers()
    if #speakers==0 then return nil,"no theater speakers present" end

    local parent=ctx.process
    local proc,err=ctx.kernel.process.create{
      ppid=parent.pid,name="cclua-theater-audio",
      uid=parent.uid,gid=parent.gid,groups=parent.groups,
      cwd=parent.cwd,capabilities=parent.capabilities,
      argv={"theater-audio",tostring(movie.id)},
    }
    if not proc then return nil,err end
    s.audio_pid=proc.pid

    ctx.kernel.scheduler:add(proc,function()
      local ok,runErr=pcall(function()
        local url=ORIGIN..tostring(movie.audio_url or "")..
          "?start="..("%.3f"):format(s.start_position or 0)
        local h,httpErr=open_stream(s,"audio",url,{
          ["Accept"]="application/octet-stream",
          ["User-Agent"]="CCLUA-Theater/0.1",
        })
        if not h then error(tostring(httpErr or "audio stream unavailable"),0) end
        local code=h.getResponseCode and h.getResponseCode() or 200
        if tonumber(code)~=200 then h.close();error("audio HTTP "..tostring(code),0) end

        if not wait_sync(s,"audio") then h.close();return end

        while s.active do
          local raw=h.read(32*1024)
          if not raw then break end
          local audio=pcm_decode(raw,s.volume)
          local pending={}
          for _,sp in ipairs(speakers) do pending[#pending+1]=sp end

          while s.active and #pending>0 do
            for i=#pending,1,-1 do
              local sp=pending[i]
              local okPlay,accepted=pcall(sp.obj.playAudio,audio,speakerOutputVolume)
              if not okPlay then
                ctx.kernel.log.write("warning","theaterd","speaker playback failed",
                  {speaker=sp.name,error=tostring(accepted)},proc.pid)
                table.remove(pending,i)
              elseif accepted then
                table.remove(pending,i)
              end
            end
            if #pending>0 then
              local ev=coroutine.yield("wait_event",{"speaker_audio_empty","terminate"})
              if ev=="terminate" then h.close();return end
            end
          end
        end
        h.close()
      end)
      if not ok then
        ctx.kernel.log.write("error","theaterd","audio stream failed",{error=tostring(runErr)},proc.pid)
        if os.queueEvent then os.queueEvent("cclua_theater_stream_error",s.token,"audio",tostring(runErr)) end
        return 1
      end
      if s.active and os.queueEvent then os.queueEvent("cclua_theater_stream_end",s.token,"audio") end
      return 0
    end)
    return true
  end

  local function spawn_video(s,movie)
    local mon=wrap_monitor(mainName)
    if not mon then return nil,"main theater monitor missing" end
    local mw,mh=mon.getSize()
    -- Maximum quality mode uses every logical cell exposed by the wall. FFmpeg
    -- preserves the source aspect ratio and letterboxes inside this canvas.
    local cols=(targetCols and targetCols>0) and math.min(targetCols,mw) or mw
    local rows=(targetRows and targetRows>0) and math.min(targetRows,mh) or mh
    cols=math.max(1,math.floor(cols))
    rows=math.max(1,math.floor(rows))
    if cols<32 or rows<12 then return nil,"main monitor is too small" end
    s.video_cols=cols;s.video_rows=rows

    local parent=ctx.process
    local proc,err=ctx.kernel.process.create{
      ppid=parent.pid,name="cclua-theater-video",
      uid=parent.uid,gid=parent.gid,groups=parent.groups,
      cwd=parent.cwd,capabilities=parent.capabilities,
      argv={"theater-video",tostring(movie.id)},
    }
    if not proc then return nil,err end
    s.video_pid=proc.pid

    ctx.kernel.scheduler:add(proc,function()
      local ok,runErr=pcall(function()
        local url=ORIGIN..tostring(movie.video_url or "")..
          ("?start=%.3f&cols=%d&rows=%d&fps=%.3f"):format(
            s.start_position or 0,cols,rows,fps)
        local h,httpErr=open_stream(s,"video",url,{
          ["Accept"]="application/octet-stream",
          ["User-Agent"]="CCLUA-Theater/0.1",
        })
        if not h then error(tostring(httpErr or "video stream unavailable"),0) end
        local code=h.getResponseCode and h.getResponseCode() or 200
        if tonumber(code)~=200 then h.close();error("video HTTP "..tostring(code),0) end

        local rowBytes=cols*3
        local frameBytes=rowBytes*rows

        -- Validate the bridge's negotiated geometry before reading a single
        -- frame. A stale bridge once clamped 167 columns to 160, which shifted
        -- every frame boundary and left playback stuck in BUFFERING.
        if h.getResponseHeaders then
          local headers=h.getResponseHeaders() or {}
          local function header(name)
            local wanted=tostring(name):lower()
            for k,v in pairs(headers) do
              if tostring(k):lower()==wanted then return tostring(v) end
            end
            return nil
          end
          local gotCols=tonumber(header("X-CCLUA-Cols"))
          local gotRows=tonumber(header("X-CCLUA-Rows"))
          local gotBytes=tonumber(header("X-CCLUA-Frame-Bytes"))
          if gotCols and gotCols~=cols then
            h.close();error(("video geometry mismatch: bridge cols=%d client cols=%d"):format(gotCols,cols),0)
          end
          if gotRows and gotRows~=rows then
            h.close();error(("video geometry mismatch: bridge rows=%d client rows=%d"):format(gotRows,rows),0)
          end
          if gotBytes and gotBytes~=frameBytes then
            h.close();error(("video frame mismatch: bridge bytes=%d client bytes=%d"):format(gotBytes,frameBytes),0)
          end
        end

        if not wait_sync(s,"video") then h.close();return end

        mon.setBackgroundColor(colors.black);mon.setTextColor(colors.white);mon.clear()
        local ox=math.floor((mw-cols)/2)+1
        local oy=math.floor((mh-rows)/2)+1
        local frame=0
        while s.active do
          local raw=read_exact(h,frameBytes)
          if not raw then break end
          frame=frame+1
          local target=(s.start_epoch or now_ms())+((frame-1)/fps)*1000
          local late=now_ms()-target

          if late<120 then
            if late<0 then coroutine.yield("sleep",math.floor(target)) end
            local off=1
            for row=0,rows-1 do
              local chars=raw:sub(off,off+cols-1);off=off+cols
              local fg=raw:sub(off,off+cols-1);off=off+cols
              local bg=raw:sub(off,off+cols-1);off=off+cols
              mon.setCursorPos(ox,oy+row)
              mon.blit(chars,fg,bg)
            end
          else
            s.dropped_frames=(s.dropped_frames or 0)+1
          end
        end
        h.close()
      end)
      if not ok then
        ctx.kernel.log.write("error","theaterd","video stream failed",{error=tostring(runErr)},proc.pid)
        if os.queueEvent then os.queueEvent("cclua_theater_stream_error",s.token,"video",tostring(runErr)) end
        return 1
      end
      if s.active and os.queueEvent then os.queueEvent("cclua_theater_stream_end",s.token,"video") end
      return 0
    end)
    return true
  end
  local function spawn_av(s,movie)
    local mon=wrap_monitor(mainName)
    if not mon then return nil,"main theater monitor missing" end
    local speakers=room_speakers()
    if #speakers==0 then return nil,"no theater speakers present" end

    local mw,mh=mon.getSize()
    local cols=(targetCols and targetCols>0) and math.min(targetCols,mw) or mw
    local rows=(targetRows and targetRows>0) and math.min(targetRows,mh) or mh
    cols=math.max(1,math.floor(cols))
    rows=math.max(1,math.floor(rows))
    if cols<32 or rows<12 then return nil,"main monitor is too small" end

    s.video_cols=cols
    s.video_rows=rows

    local parent=ctx.process
    local proc,err=ctx.kernel.process.create{
      ppid=parent.pid,name="cclua-theater-av",
      uid=parent.uid,gid=parent.gid,groups=parent.groups,
      cwd=parent.cwd,capabilities=parent.capabilities,
      argv={"theater-av",tostring(movie.id)},
    }
    if not proc then return nil,err end
    s.av_pid=proc.pid

    ctx.kernel.scheduler:add(proc,function()
      local ok,runErr=pcall(function()
        local url=ORIGIN.."/v1/movies/"..tostring(movie.id).."/av.stream"..
          ("?start=%.3f&cols=%d&rows=%d&fps=%.3f"):format(
            s.start_position or 0,cols,rows,fps)

        local h,httpErr=open_stream(s,"av",url,{
          ["Accept"]="application/octet-stream",
          ["User-Agent"]="CCLUA-Theater/0.2",
        })
        if not h then error(tostring(httpErr or "A/V stream unavailable"),0) end

        local code=h.getResponseCode and h.getResponseCode() or 200
        if tonumber(code)~=200 then h.close();error("A/V HTTP "..tostring(code),0) end

        local headers=h.getResponseHeaders and h.getResponseHeaders() or {}
        local function header(name)
          local wanted=tostring(name):lower()
          for k,v in pairs(headers) do
            if tostring(k):lower()==wanted then return tostring(v) end
          end
          return nil
        end

        local format=header("X-CCLUA-Format")
        local gotCols=tonumber(header("X-CCLUA-Cols")) or cols
        local gotRows=tonumber(header("X-CCLUA-Rows")) or rows
        local gotFps=tonumber(header("X-CCLUA-FPS")) or fps
        local frameBytes=tonumber(header("X-CCLUA-Frame-Bytes")) or (cols*rows*3)
        local audioBytes=tonumber(header("X-CCLUA-Audio-Bytes")) or math.floor(48000/fps+0.5)
        local sampleRate=tonumber(header("X-CCLUA-Sample-Rate")) or 48000

        if format and format~="av-blit-pcm-v1" then
          h.close();error("unsupported A/V stream format: "..tostring(format),0)
        end
        if gotCols~=cols or gotRows~=rows then
          h.close();error(("A/V geometry mismatch: bridge=%dx%d client=%dx%d"):format(
            gotCols,gotRows,cols,rows),0)
        end
        if frameBytes~=cols*rows*3 then
          h.close();error(("A/V frame mismatch: bridge bytes=%d client bytes=%d"):format(
            frameBytes,cols*rows*3),0)
        end
        if math.abs(gotFps-fps)>0.01 then
          h.close();error(("A/V FPS mismatch: bridge=%.3f client=%.3f"):format(gotFps,fps),0)
        end
        if sampleRate~=48000 or audioBytes<1 then
          h.close();error("unsupported A/V audio geometry",0)
        end

        s.audio_bytes=audioBytes
        s.av_stage="prebuffering"

        -- Do not declare playback ready until one complete synchronized packet
        -- has arrived. This prevents an HTTP connection with no payload from
        -- leaving the theater in a permanent BUFFERING state.
        local videoRaw=read_exact(h,frameBytes)
        local audioRaw=read_exact(h,audioBytes)
        if not videoRaw or not audioRaw then
          h.close();error("A/V stream ended during prebuffer",0)
        end

        s.av_ready=true
        s.av_stage="ready"
        s.start_epoch=now_ms()+250
        s.go=true

        mon.setBackgroundColor(colors.black)
        mon.setTextColor(colors.white)
        mon.clear()
        local ox=math.floor((mw-cols)/2)+1
        local oy=math.floor((mh-rows)/2)+1
        local frame=0

        local function present(video,audioRaw)
          frame=frame+1
          local target=(s.start_epoch or now_ms())+((frame-1)/fps)*1000
          if now_ms()<target then coroutine.yield("sleep",math.floor(target)) end
          local late=now_ms()-target

          if late<120 then
            local off=1
            for row=0,rows-1 do
              local chars=video:sub(off,off+cols-1);off=off+cols
              local fg=video:sub(off,off+cols-1);off=off+cols
              local bg=video:sub(off,off+cols-1);off=off+cols
              mon.setCursorPos(ox,oy+row)
              mon.blit(chars,fg,bg)
            end
          else
            s.dropped_frames=(s.dropped_frames or 0)+1
          end

          local audio=pcm_decode(audioRaw,s.volume)
          local pending={}
          for _,sp in ipairs(speakers) do pending[#pending+1]=sp end
          while s.active and #pending>0 do
            for i=#pending,1,-1 do
              local sp=pending[i]
              local okPlay,accepted=pcall(sp.obj.playAudio,audio,speakerOutputVolume)
              if not okPlay then
                ctx.kernel.log.write("warning","theaterd","speaker playback failed",
                  {speaker=sp.name,error=tostring(accepted)},proc.pid)
                table.remove(pending,i)
              elseif accepted then
                table.remove(pending,i)
              end
            end
            if #pending>0 then
              local ev=coroutine.yield("wait_event",{"speaker_audio_empty","terminate"})
              if ev=="terminate" then return false end
            end
          end
          return s.active
        end

        s.av_stage="playing"
        while s.active do
          if not present(videoRaw,audioRaw) then break end
          videoRaw=read_exact(h,frameBytes)
          if not videoRaw then break end
          audioRaw=read_exact(h,audioBytes)
          if not audioRaw then break end
        end
        h.close()
      end)

      if not ok then
        ctx.kernel.log.write("error","theaterd","A/V stream failed",{error=tostring(runErr)},proc.pid)
        if os.queueEvent then os.queueEvent("cclua_theater_stream_error",s.token,"av",tostring(runErr)) end
        return 1
      end
      if s.active and os.queueEvent then os.queueEvent("cclua_theater_stream_end",s.token,"av") end
      return 0
    end)
    return true
  end
  local function segment_header(headers,name)
    local wanted=tostring(name):lower()
    for k,v in pairs(headers or {}) do
      if tostring(k):lower()==wanted then return tostring(v) end
    end
    return nil
  end

  local function parse_palette_hex(raw)
    raw=tostring(raw or ""):lower()
    if #raw~=96 or raw:find("[^0-9a-f]") then return nil end
    local palette={}
    for i=0,15 do
      local off=i*6+1
      local r=tonumber(raw:sub(off,off+1),16)
      local g=tonumber(raw:sub(off+2,off+3),16)
      local b=tonumber(raw:sub(off+4,off+5),16)
      if not r or not g or not b then return nil end
      palette[i+1]={r,g,b}
    end
    return palette
  end

  local function parse_palette_sequence(raw,count)
    raw=tostring(raw or ""):lower()
    count=math.floor(tonumber(count) or 0)
    if count<1 or count>16 or #raw~=count*96 or raw:find("[^0-9a-f]") then
      return nil
    end
    local palettes={}
    local keys={}
    for i=1,count do
      local first=(i-1)*96+1
      local hex=raw:sub(first,first+95)
      local palette=parse_palette_hex(hex)
      if not palette then return nil end
      palettes[i]=palette
      keys[i]=hex
    end
    return palettes,keys
  end

  local function request_segment(s,index)
    if not s or not s.active then return nil,"session stopped" end
    index=math.max(0,math.floor(tonumber(index) or 0))
    if s.segments[index] or s.segment_requested[index] then return true end
    if s.segment_inflight then return false,"segment request already in flight" end

    local start=(s.start_position or 0)+index*s.segment_seconds
    local duration=tonumber(s.movie and s.movie.duration)
    if duration and start>=duration-0.01 then
      s.segment_eof=index
      return false,"end of movie"
    end

    local colorRequest=s.rgb24 and "rgb24" or "adaptive16x4"
    local url=ORIGIN.."/v1/movies/"..tostring(s.movie.id).."/av.segment"..
      ("?start=%.3f&seconds=%.3f&cols=%d&rows=%d&fps=%.3f&color=%s&session=%d&seq=%d"):format(
        start,s.segment_seconds,s.video_cols,s.video_rows,fps,colorRequest,s.token,index)

    local ok,err=http.request{
      url=url,
      method="GET",
      headers={
        ["Accept"]="application/octet-stream",
        ["User-Agent"]="CCLUA-Theater/0.3",
      },
      binary=true,
      timeout=20,
    }
    if not ok then
      return nil,tostring(err or "segment request failed")
    end

    s.segment_requested[index]=true
    s.segment_inflight={url=url,index=index,start=start,requested_at=now_ms()}
    s.av_stage=index==0 and "buffering first segment" or ("prefetch segment "..index)
    return true
  end

  local function ensure_segment_prefetch(s)
    if not s or not s.active or s.segment_inflight then return end
    local first=math.max(0,tonumber(s.play_index) or 0)
    local limit=first+segmentPrefetch
    for index=first,limit do
      if not s.segments[index] and not s.segment_requested[index]
        and not s.segment_consumed[index]
        and (not s.segment_eof or index<s.segment_eof) then
        local ok,err=request_segment(s,index)
        if not ok and err~="end of movie" and err~="segment request already in flight" then
          s.av_last_error=err
        end
        return
      end
    end
  end

  local function accept_segment_response(s,url,h)
    local req=s and s.segment_inflight
    if not req or req.url~=url then
      if h and h.close then pcall(h.close) end
      return false
    end
    s.segment_inflight=nil

    local code=h.getResponseCode and h.getResponseCode() or 200
    local headers=h.getResponseHeaders and h.getResponseHeaders() or {}
    if tonumber(code)~=200 then
      if h.close then pcall(h.close) end
      s.segment_requested[req.index]=nil
      s.segment_retries[req.index]=(s.segment_retries[req.index] or 0)+1
      if s.segment_retries[req.index]<=3 then
        ensure_segment_prefetch(s)
      else
        if os.queueEvent then
          os.queueEvent("cclua_theater_stream_error",s.token,"av",
            "segment HTTP "..tostring(code))
        end
      end
      return false
    end

    local format=segment_header(headers,"X-CCLUA-Format")
    local cols=tonumber(segment_header(headers,"X-CCLUA-Cols")) or s.video_cols
    local rows=tonumber(segment_header(headers,"X-CCLUA-Rows")) or s.video_rows
    local gotFps=tonumber(segment_header(headers,"X-CCLUA-FPS")) or fps
    local frameBytes=tonumber(segment_header(headers,"X-CCLUA-Frame-Bytes"))
      or (s.video_cols*s.video_rows*3)
    local audioBytes=tonumber(segment_header(headers,"X-CCLUA-Audio-Bytes"))
      or math.floor(48000/fps+0.5)
    local sampleRate=tonumber(segment_header(headers,"X-CCLUA-Sample-Rate")) or 48000
    local packets=tonumber(segment_header(headers,"X-CCLUA-Packets")) or 0
    local paletteHex=segment_header(headers,"X-CCLUA-Palette-RGB")
    local paletteSequenceHex=segment_header(headers,"X-CCLUA-Palette-RGB-Sequence")
    local paletteCount=tonumber(segment_header(headers,"X-CCLUA-Palette-Count")) or 0
    local paletteFrames=tonumber(segment_header(headers,"X-CCLUA-Palette-Frames")) or 0
    local colorMode=segment_header(headers,"X-CCLUA-Color-Mode") or "stock16"
    local palette=paletteHex and parse_palette_hex(paletteHex) or nil
    local palettes,paletteKeys=nil,nil
    if paletteSequenceHex then
      palettes,paletteKeys=parse_palette_sequence(paletteSequenceHex,paletteCount)
    end
    local raw
    if type(h.read)=="function" then
      local parts={}
      local total=0
      while true do
        local chunk=h.read(131072)
        if not chunk or #chunk==0 then break end
        parts[#parts+1]=chunk
        total=total+#chunk
        -- Yield between bounded reads so large RGB segments cannot monopolize
        -- the cooperative scheduler and freeze both PCM and video.
        coroutine.yield("sleep",now_ms()+1)
      end
      raw=table.concat(parts)
    else
      raw=h.readAll() or ""
    end
    if h.close then pcall(h.close) end

    local packetBytes=frameBytes+audioBytes
    if format~="av-segment-v1" then
      error("unsupported theater segment format: "..tostring(format),0)
    end
    if cols~=s.video_cols or rows~=s.video_rows then
      error(("segment geometry mismatch: bridge=%dx%d client=%dx%d"):format(
        cols,rows,s.video_cols,s.video_rows),0)
    end
    if math.abs(gotFps-fps)>0.01 or sampleRate~=48000 then
      error("segment timing geometry mismatch",0)
    end
    local expectedFrameBytes=colorMode=="rgb24"
      and (s.video_cols*2)*(s.video_rows*3)*3
      or s.video_cols*s.video_rows*3
    if frameBytes~=expectedFrameBytes or audioBytes<1 then
      error("segment packet geometry mismatch",0)
    end
    if colorMode=="rgb24" and not s.rgb24 then
      error("bridge selected RGB24 but CCPerf RGB framebuffer is unavailable",0)
    end
    if packets<1 then
      error("empty theater segment",0)
    end
    if #raw~=packets*packetBytes then
      error(("segment length mismatch: got %d expected %d"):format(
        #raw,packets*packetBytes),0)
    end
    if colorMode=="adaptive16-bayer4" and not palette then
      error("adaptive theater segment is missing a valid 16-color RGB palette",0)
    end
    if colorMode=="adaptive16x4-fs" then
      if not palettes or #palettes<1 then
        error("cinema color segment is missing its palette sequence",0)
      end
      paletteFrames=math.max(1,math.floor(paletteFrames))
      if paletteFrames>packets then
        error("cinema color palette cadence exceeds segment packet count",0)
      end
    end

    s.segment_requested[req.index]=nil
    s.segment_retries[req.index]=nil
    s.segments[req.index]={
      raw=raw,index=req.index,start=req.start,
      packets=packets,frame_bytes=frameBytes,audio_bytes=audioBytes,
      packet_bytes=packetBytes,duration=packets/gotFps,
      palette=palette,palette_hex=paletteHex,
      palettes=palettes,palette_keys=paletteKeys,palette_frames=paletteFrames,
      palette_count=palettes and #palettes or 0,color_mode=colorMode,
      received_at=now_ms(),request_ms=now_ms()-(req.requested_at or now_ms()),
    }
    s.audio_bytes=audioBytes
    s.color_mode=colorMode
    s.av_ready=true
    s.av_stage=req.index==0 and "ready" or ("buffered segment "..req.index)
    ensure_segment_prefetch(s)
    return true
  end

  local function fail_segment_response(s,url,err,h)
    if h and h.close then pcall(h.close) end
    local req=s and s.segment_inflight
    if not req or req.url~=url then return false end
    s.segment_inflight=nil
    s.segment_requested[req.index]=nil
    s.segment_retries[req.index]=(s.segment_retries[req.index] or 0)+1
    s.av_last_error=tostring(err or "segment request failed")
    if s.segment_retries[req.index]<=3 then
      ensure_segment_prefetch(s)
    elseif os.queueEvent then
      os.queueEvent("cclua_theater_stream_error",s.token,"av",s.av_last_error)
    end
    return true
  end

  local function spawn_segment_player(s,movie)
    local mon=wrap_monitor(mainName)
    if not mon then return nil,"main theater monitor missing" end
    local speakers=room_speakers()
    if #speakers==0 then return nil,"no theater speakers present" end

    local mw,mh=mon.getSize()
    local cols=(targetCols and targetCols>0) and math.min(targetCols,mw) or mw
    local rows=(targetRows and targetRows>0) and math.min(targetRows,mh) or mh
    cols=math.max(1,math.floor(cols))
    rows=math.max(1,math.floor(rows))
    if cols<32 or rows<12 then return nil,"main monitor is too small" end
    s.video_cols=cols
    s.video_rows=rows
    -- CCPerf exposes the framebuffer as a generic monitor extension. Theater
    -- only consumes that API; it has no renderer-specific monitor hooks.
    s.rgb24=type(mon.framebufferInfo)=="function" and
      type(mon.framebufferCreate)=="function" and
      type(mon.framebufferWrite)=="function" and
      type(mon.framebufferPresent)=="function"
    if s.rgb24 then
      local okInfo,info=pcall(mon.framebufferInfo)
      s.rgb24=okInfo and type(info)=="table" and info.format=="rgb888"
    end
    s.rgb_width=cols*2
    s.rgb_height=rows*3

    local parent=ctx.process
    local proc,err=ctx.kernel.process.create{
      ppid=parent.pid,name="cclua-theater-segment-player",
      uid=parent.uid,gid=parent.gid,groups=parent.groups,
      cwd=parent.cwd,capabilities=parent.capabilities,
      argv={"theater-segment-player",tostring(movie.id)},
    }
    if not proc then return nil,err end
    s.av_pid=proc.pid

    ctx.kernel.scheduler:add(proc,function()
      local ok,runErr=pcall(function()
        mon.setBackgroundColor(colors.black)
        mon.setTextColor(colors.white)
        mon.clear()
        local ox=math.floor((mw-cols)/2)+1
        local oy=math.floor((mh-rows)/2)+1

        while s.active do
          if (s.play_index or 0)==0 and not s.go then
            while s.active do
              local ready=0
              for i=0,initialBufferSegments-1 do
                if s.segments[i] then ready=ready+1 end
              end
              if ready>=initialBufferSegments or
                (s.segment_eof and s.segment_eof<=initialBufferSegments) then
                break
              end
              s.av_stage=("prebuffer %d/%d segments"):format(ready,initialBufferSegments)
              coroutine.yield("sleep",now_ms()+15)
            end
          end

          local index=s.play_index or 0
          local seg=s.segments[index]
          if not seg then
            if s.segment_eof and index>=s.segment_eof then break end
            s.av_stage=index==0 and "buffering first segment"
              or ("waiting segment "..index)
            coroutine.yield("sleep",now_ms()+15)
          else
            s.segments[index]=nil
            s.segment_consumed[index]=true
            if seg.palette then
              apply_main_palette(mon,seg.palette,seg.palette_hex)
            end

            if not s.go then
              s.start_epoch=now_ms()+120
              s.go=true
              state.state="PLAYING"
              state.position=s.start_position or 0
              save_state()
            end

            local segmentTarget=(s.start_epoch or now_ms())+
              ((seg.start-(s.start_position or 0))*1000)
            if now_ms()<segmentTarget then
              coroutine.yield("sleep",math.floor(segmentTarget))
            end

            local acceptedCount=0
            local failedCount=0
            s.speaker_submit_ok=0
            s.speaker_submit_failed=0
            s.speaker_submit_total=#speakers
            s.speaker_output_volume=speakerOutputVolume

            local packetOffset=1
            local activePaletteIndex=nil
            for packet=0,seg.packets-1 do
              if not s.active then break end

              if seg.palettes and #seg.palettes>0 then
                local paletteFrames=math.max(1,tonumber(seg.palette_frames) or seg.packets)
                local paletteIndex=math.min(#seg.palettes,math.floor(packet/paletteFrames)+1)
                if paletteIndex~=activePaletteIndex then
                  apply_main_palette(
                    mon,
                    seg.palettes[paletteIndex],
                    seg.palette_keys and seg.palette_keys[paletteIndex] or
                      (tostring(seg.index)..":"..tostring(paletteIndex))
                  )
                  activePaletteIndex=paletteIndex
                end
              end

              local target=segmentTarget+(packet/fps)*1000
              if now_ms()<target then coroutine.yield("sleep",math.floor(target)) end
              local late=now_ms()-target

              -- Keep the bridge's native 50 ms / 2400-sample packetization.
              -- Giant segment-sized playAudio buffers cause poor OpenAL
              -- streaming behaviour and make individual sources fall behind.
              -- Audio bytes are interleaved with every video frame:
              -- [frame][2400 PCM bytes][frame][2400 PCM bytes]...
              -- seg.audio_bytes is therefore the per-frame block size, not
              -- the whole segment. Keep this guard explicit so a malformed
              -- bridge response can never turn into multi-second playAudio.
              local audioStart=packetOffset+seg.frame_bytes
              local audioEnd=audioStart+seg.audio_bytes-1
              local audioRaw=seg.raw:sub(audioStart,audioEnd)
              if #audioRaw~=seg.audio_bytes then
                error(("audio packet %d has %d bytes; expected %d"):format(
                  packet,#audioRaw,seg.audio_bytes),0)
              end
              local audio=pcm_decode(audioRaw,s.volume)
              -- Audio and video share this packet's media timestamp, but
              -- video must never block behind an individual OpenAL speaker.
              -- Submit the entire 22-speaker epoch once. If any source is
              -- backpressured, drop that source's late epoch and let the next
              -- 50 ms packet recover it; waiting for speaker_audio_empty here
              -- used to freeze the corresponding video frame indefinitely.
              local acceptedThisEpoch=0
              local rejectedThisEpoch=0
              for _,sp in ipairs(speakers) do
                local okPlay,accepted=pcall(sp.obj.playAudio,audio,speakerOutputVolume)
                if not okPlay then
                  failedCount=failedCount+1
                  rejectedThisEpoch=rejectedThisEpoch+1
                  ctx.kernel.log.write("warning","theaterd","speaker playback failed",
                    {speaker=sp.name,error=tostring(accepted)},proc.pid)
                elseif accepted then
                  acceptedCount=acceptedCount+1
                  acceptedThisEpoch=acceptedThisEpoch+1
                else
                  rejectedThisEpoch=rejectedThisEpoch+1
                end
              end
              s.speaker_submit_ok=acceptedThisEpoch
              s.speaker_submit_failed=rejectedThisEpoch
              s.speaker_submit_total=#speakers
              s.audio_epoch=packet
              s.audio_target_ms=target
              s.audio_late_ms=late

              -- Audio is the media clock. Present only a frame that is still
              -- close to its matching PCM epoch; late frames are discarded
              -- instead of being shown after their sound has already played.
              if late<120 then
                local video=seg.raw:sub(packetOffset,packetOffset+seg.frame_bytes-1)
                if seg.color_mode=="rgb24" and s.rgb24 then
                  if not s.rgb_initialized then
                    mon.framebufferCreate(s.rgb_width,s.rgb_height)
                    s.rgb_initialized=true
                  end
                  local chunkBytes=24576
                  local off=1
                  while off<=#video do
                    local last=math.min(#video,off+chunkBytes-1)
                    mon.framebufferWrite(off-1,video:sub(off,last))
                    off=last+1
                  end
                  mon.framebufferPresent()
                else
                  local voff=1
                  for row=0,rows-1 do
                    local chars=video:sub(voff,voff+cols-1);voff=voff+cols
                    local fg=video:sub(voff,voff+cols-1);voff=voff+cols
                    local bg=video:sub(voff,voff+cols-1);voff=voff+cols
                    mon.setCursorPos(ox,oy+row)
                    mon.blit(chars,fg,bg)
                  end
                end
              else
                s.dropped_frames=(s.dropped_frames or 0)+1
              end
              packetOffset=packetOffset+seg.packet_bytes
            end

            s.play_index=index+1
            s.av_stage="playing"
            if os.queueEvent then os.queueEvent("cclua_theater_prefetch",s.token) end
          end
        end
      end)

      if not ok then
        ctx.kernel.log.write("error","theaterd","segmented A/V playback failed",
          {error=tostring(runErr)},proc.pid)
        if os.queueEvent then
          os.queueEvent("cclua_theater_stream_error",s.token,"av",tostring(runErr))
        end
        return 1
      end
      if s.active and os.queueEvent then
        os.queueEvent("cclua_theater_stream_end",s.token,"av")
      end
      return 0
    end)
    return true
  end

  local function start_movie(movie,position)
    if not movie then return nil,"movie metadata required" end
    stop_session(false)
    sessionSeq=sessionSeq+1
    local s={
      token=sessionSeq,active=true,go=false,
      start_position=math.max(0,tonumber(position) or 0),
      volume=state.volume,
      movie=movie,
      dropped_frames=0,
      segment_seconds=segmentSeconds,
      play_index=0,
      segments={},
      segment_requested={},
      segment_consumed={},
      segment_retries={},
      segment_inflight=nil,
      segment_eof=nil,
    }
    session=s
    state.movie_id=movie.id
    state.title=movie.title or "Unknown"
    state.duration=tonumber(movie.duration)
    state.position=s.start_position
    state.state="BUFFERING"
    state.error=nil
    lastRenderKey.main=nil

    local avok,averr=spawn_segment_player(s,movie)
    if not avok then
      stop_session(false)
      state.state="ERROR"
      state.error=tostring(averr)
      save_state();render_all()
      return nil,state.error
    end
    local reqok,reqerr=request_segment(s,0)
    if not reqok then
      stop_session(false)
      state.state="ERROR"
      state.error=tostring(reqerr or "could not start theater segment")
      save_state();render_all()
      return nil,state.error
    end
    save_state();render_all()
    return true
  end

  local function play_id(id)
    local movie,index=find_movie(id)
    if not movie then return nil,"movie not found" end
    state.selected_index=index
    local ok,err=start_movie(movie,0)
    if ok then set_scene("feature",true) end
    return ok,err
  end

  local function pause_movie()
    if state.state~="PLAYING" and state.state~="BUFFERING" then return false end
    stop_session(true)
    state.state="PAUSED"
    state.error=nil
    lastRenderKey.main=nil
    save_state();render_all()
    return true
  end

  local function resume_movie()
    if state.state~="PAUSED" or not state.movie_id then return false end
    local movie=find_movie(state.movie_id)
    if not movie then return nil,"movie unavailable" end
    return start_movie(movie,state.position or 0)
  end

  local function stop_movie(returnHouse)
    stop_session(false)
    state.state="IDLE"
    state.position=0
    state.movie_id=nil
    state.title=nil
    state.duration=nil
    state.error=nil
    lastRenderKey.main=nil
    if returnHouse~=false then set_scene("house",true) end
    save_state();render_all()
    return true
  end

  local function seek_movie(delta)
    if not state.movie_id then return false end
    local movie=find_movie(state.movie_id)
    if not movie then return nil,"movie unavailable" end
    local wasPlaying=state.state=="PLAYING" or state.state=="BUFFERING"
    local pos=clamp(current_position()+(tonumber(delta) or 0),0,math.max(0,(tonumber(movie.duration) or 1)-0.05))
    stop_session(false)
    state.position=pos
    if wasPlaying then return start_movie(movie,pos) end
    state.state="PAUSED";lastRenderKey.main=nil;save_state();render_all()
    return true
  end

  local function set_volume(payload)
    local value=payload and tonumber(payload.value)
    if value==nil then value=(state.volume or 0.85)+(payload and tonumber(payload.delta) or 0) end
    state.volume=clamp(value,0,1)
    if session then session.volume=state.volume end
    save_state();render_all()
    return true
  end

  local function handle_command(op,payload)
    payload=type(payload)=="table" and payload or {}
    if op=="scene" then return set_scene(payload.scene,true)
    elseif op=="brightness" then
      state.scene="custom";set_brightness(payload.value,true);save_state();render_all();return true
    elseif op=="play" then return play_id(payload.id)
    elseif op=="pause" then return pause_movie()
    elseif op=="resume" then return resume_movie()
    elseif op=="toggle" then
      if state.state=="PLAYING" or state.state=="BUFFERING" then return pause_movie()
      elseif state.state=="PAUSED" then return resume_movie()
      elseif catalog[state.selected_index or 1] then return play_id(catalog[state.selected_index or 1].id) end
      return false
    elseif op=="stop" then return stop_movie(true)
    elseif op=="seek" then return seek_movie(payload.delta)
    elseif op=="volume" then return set_volume(payload)
    elseif op=="select" then
      state.selected_index=math.max(1,math.min(math.max(1,#catalog),tonumber(payload.index) or state.selected_index or 1))
      save_state();render_all();return true
    elseif op=="refresh" then refresh_catalog();hardware_snapshot();save_state();render_all();return true
    end
    return nil,"unknown theater operation"
  end

  local function touch_transport(x,y)
    local mon=wrap_monitor(transportName)
    if not mon then return end
    local w,h=mon.getSize()
    if y>=h-2 then
      if x<=math.floor(w/3) then seek_movie(-10)
      elseif x>=math.floor(w*2/3) then seek_movie(10)
      else handle_command("toggle",{}) end
    elseif y==7 then
      if x<math.floor(w/2) then set_volume({delta=-0.05}) else set_volume({delta=0.05}) end
    end
  end

  local function touch_control(x,y)
    local mon=wrap_monitor(controlName)
    if not mon then return end
    local w,h=mon.getSize()
    local sceneRow=y-3
    if sceneRow>=1 and sceneRow<=#sceneOrder then
      set_scene(sceneOrder[sceneRow],true)
      return
    end
    local maxScenes=math.min(#sceneOrder,math.max(0,h-8))
    local movieStartY=4+maxScenes+2
    if y>=movieStartY and y<=h-2 then
      local first=math.max(1,math.min(#catalog,tonumber(state.selected_index) or 1)-1)
      local idx=first+(y-movieStartY)
      if catalog[idx] then
        state.selected_index=idx
        play_id(catalog[idx].id)
      end
    end
  end
  configure_monitors()
  hardware_snapshot()
  refresh_catalog()

  -- Reconcile the actual fixture state before applying the persisted scene.
  for _,f in ipairs(fixtures) do
    if peripheral_ok(f.name,"redstone_relay") then
      local relay=peripheral.wrap(f.name)
      local ok,v=pcall(relay.getOutput,"bottom")
      fixtureOn[f.id]=ok and v==true or false
    end
  end
  set_scene(state.scene,true)
  state.state="IDLE"
  save_state()
  render_all()

  ctx.unit.details={
    bridge=BRIDGE,main_monitor=mainName,
    transport_monitor=transportName,control_monitor=controlName,
    speakers=expectedRoomSpeakers,fixtures=#fixtures,video={cols=targetCols,rows=targetRows,fps=fps}
  }
  ctx.kernel.log.write("info","theaterd","theater controller online",ctx.unit.details,ctx.process.pid)

  local refreshTimer=os.startTimer(0.25)
  local catalogTimer=os.startTimer(5)
  while true do
    local ev,a,b,c=coroutine.yield("wait_event",{
      "timer","cclua_theater_command","cclua_theater_stream_ready",
      "cclua_theater_stream_end","cclua_theater_stream_error",
      "cclua_theater_prefetch","http_success","http_failure",
      "monitor_touch","monitor_resize","peripheral","peripheral_detach","terminate"
    })

    if ev=="terminate" then
      stop_session(true)
      save_state()
      return 0

    elseif ev=="timer" and lightAnimation and a==lightAnimation.timer then
      step_light_animation()

    elseif ev=="timer" and a==refreshTimer then
      if fs and fs.exists and fs.exists(COMMAND_PATH) then
        local command=config.read_json(COMMAND_PATH,nil)
        pcall(fs.delete,COMMAND_PATH)
        if type(command)=="table" and command.op then
          local ok,err=handle_command(tostring(command.op),command.payload or {})
          if not ok and err then
            state.error=tostring(err)
            ctx.kernel.log.write("warning","theaterd","mailbox command failed",
              {op=command.op,error=err},ctx.process.pid)
          end
        end
      end
      if session and session.active then
        local avp=session.av_pid and ctx.kernel.process.get(session.av_pid) or nil
        local buffered=0
        for _ in pairs(session.segments or {}) do buffered=buffered+1 end
        state.streams={
          av={
            pid=session.av_pid,state=avp and avp.state or "missing",
            stage=session.av_stage or "spawned",ready=session.av_ready==true,
            last_error=session.av_last_error,
            cols=session.video_cols,rows=session.video_rows,
            audio_bytes=session.audio_bytes,
            play_index=session.play_index or 0,
            buffered_segments=buffered,
            inflight_index=session.segment_inflight and session.segment_inflight.index or nil,
            segment_seconds=session.segment_seconds,
            initial_buffer_segments=initialBufferSegments,
            color_mode=session.color_mode,
            speaker_submit_ok=session.speaker_submit_ok,
            speaker_submit_failed=session.speaker_submit_failed,
            speaker_submit_total=session.speaker_submit_total,
            speaker_output_volume=session.speaker_output_volume,
          },
        }
        if session.go then
          if state.state=="BUFFERING" then state.state="PLAYING" end
          state.position=current_position()
          state.dropped_frames=session.dropped_frames or 0
          if state.duration and state.position>state.duration then state.position=state.duration end
        end
      else
        state.streams=nil
      end
      hardware_snapshot()
      save_state()
      render_transport()
      refreshTimer=os.startTimer(0.25)

    elseif ev=="timer" and a==catalogTimer then
      refresh_catalog()
      catalogTimer=os.startTimer(5)

    elseif ev=="cclua_theater_command" then
      local ok,err=handle_command(tostring(a or ""),b)
      if not ok and err then
        state.error=tostring(err)
        ctx.kernel.log.write("warning","theaterd","command failed",{op=a,error=err},ctx.process.pid)
      end

    elseif ev=="cclua_theater_prefetch" and session and a==session.token then
      ensure_segment_prefetch(session)

    elseif ev=="http_success" then
      local url=tostring(a or "")
      if url==catalogUrl then
        catalogInflight=false
        local h=b
        local code=h and h.getResponseCode and h.getResponseCode() or 200
        local raw=h and h.readAll and h.readAll() or ""
        if h and h.close then pcall(h.close) end
        if tonumber(code)==200 then
          local ok,data=pcall(textutils.unserializeJSON,raw)
          if ok and type(data)=="table" then
            apply_catalog(data)
          else
            state.bridge="OFFLINE"
            state.bridge_error="invalid bridge JSON"
          end
        else
          state.bridge="OFFLINE"
          state.bridge_error="HTTP "..tostring(code)
        end
      elseif session and session.active and session.segment_inflight
        and session.segment_inflight.url==url then
        local ok,err=pcall(accept_segment_response,session,url,b)
        if not ok then
          ctx.kernel.log.write("error","theaterd","segment response validation failed",
            {error=tostring(err),url=url},ctx.process.pid)
          if os.queueEvent then
            os.queueEvent("cclua_theater_stream_error",session.token,"av",tostring(err))
          end
        end
      end

    elseif ev=="http_failure" then
      local url=tostring(a or "")
      if url==catalogUrl then
        catalogInflight=false
        state.bridge="OFFLINE"
        state.bridge_error=tostring(b or "Could not connect")
      elseif session and session.active and session.segment_inflight
        and session.segment_inflight.url==url then
        fail_segment_response(session,url,b,c)
      end

    elseif ev=="cclua_theater_stream_ready" and session and a==session.token then
      if session.audio_ready and session.video_ready and not session.go then
        session.start_epoch=now_ms()+120
        session.go=true
        state.state="PLAYING"
        state.position=session.start_position or 0
        save_state();render_transport()
        if os.queueEvent then os.queueEvent("cclua_theater_sync",session.token) end
      end

    elseif ev=="cclua_theater_stream_end" and session and a==session.token then
      local kind=tostring(b or "")
      session[kind.."_ended"]=true
      if kind=="av" then
        if state.duration and current_position()>=state.duration-1.5 then
          stop_movie(true)
        else
          stop_session(true)
          state.state="ERROR"
          state.error="A/V stream ended before the feature completed"
          lastRenderKey.main=nil
          save_state();render_all()
        end
      elseif session.audio_ended or session.video_ended then
        if state.duration and current_position()>=state.duration-1.5 then
          stop_movie(true)
        end
      end

    elseif ev=="cclua_theater_stream_error" and session and a==session.token then
      local kind,err=tostring(b or ""),tostring(c or "stream failed")
      stop_session(true)
      state.state="ERROR";state.error=kind..": "..err
      lastRenderKey.main=nil
      save_state();render_all()

    elseif ev=="monitor_touch" then
      if a==transportName then touch_transport(tonumber(b) or 1,tonumber(c) or 1)
      elseif a==controlName then touch_control(tonumber(b) or 1,tonumber(c) or 1) end

    elseif ev=="monitor_resize" or ev=="peripheral" or ev=="peripheral_detach" then
      monitorCache={}
      configure_monitors()
      hardware_snapshot()
      lastRenderKey.main=nil
      save_state();render_all()
    end
  end
end
