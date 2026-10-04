local M={}
local Music=dofile("/usr/lib/cclua/desktop/music.lua")

local tabs={"Library","Spotify","Direct"}

local function refresh(st)
  local tracks,bridgeErr=Music.catalog()
  st.tracks=tracks or {}
  st.bridge_error=bridgeErr
  st.selected=math.max(1,math.min(math.max(1,#st.tracks),st.selected or 1))
  st.scroll=math.max(1,math.min(st.scroll or 1,math.max(1,#st.tracks)))
end

function M.new(ctx)
  local st={
    title="Music",icon="Mu",tab=1,selected=1,scroll=1,
    tracks={},input="",message=nil,spotify=nil,match=nil,
    direct_name="download.dfpwm"
  }
  refresh(st)
  return st
end

local function fit(s,w)
  s=tostring(s or "")
  if #s<=w then return s end
  return s:sub(1,math.max(1,w-1)).."~"
end

local function selected(st)
  return (st.tracks or {})[st.selected]
end

local function draw_tabs(st,ui,x,y)
  local tx=x+1
  for i,label in ipairs(tabs) do
    local bg=i==st.tab and colors.gray or colors.black
    local fg=i==st.tab and colors.white or colors.lightGray
    ui.text(tx,y," "..label.." ",fg,bg)
    tx=tx+#label+3
  end
end

local function format_duration(sec)
  sec=tonumber(sec)
  if not sec then return "--:--" end
  sec=math.max(0,sec)
  return ("%d:%02d"):format(math.floor(sec/60),math.floor(sec%60))
end

local function play_selected(ctx,st,track)
  track=track or selected(st)
  if not track then return nil,"no track selected" end
  local state=Music.playback_state()
  return Music.play_from_queue(ctx,st.tracks,st.selected,nil,state.volume)
end

local function draw_transport(ctx,st,ui,x,y,w,h)
  local state=Music.playback_state()
  local now=state.player
  local top=y+h-6

  ui.fill(x,top,x+w-1,y+h-2,colors.black,colors.white)
  ui.fill(x,top,x+w-1,top,colors.gray,colors.white)

  if not now then
    ui.text(x+1,top,"No track playing",colors.lightGray,colors.gray)
    ui.text(x+1,top+1,"[------------------------]  --:-- / --:--",colors.gray,colors.black)
  else
    local status=now.state=="paused" and "PAUSED" or "PLAYING"
    local label=(now.artist and now.artist~="") and (now.artist.." - "..now.title) or now.title
    ui.text(x+1,top,fit(status.."  "..label,math.max(1,w-18)),
      now.state=="paused" and colors.yellow or colors.lime,colors.gray)
    local quality=tostring(now.format or "audio")
    ui.text(x+w-#quality-1,top,quality,colors.white,colors.gray)

    local duration=tonumber(now.duration) or 0
    local position=math.max(0,tonumber(now.position) or 0)
    local barW=math.max(8,w-19)
    local pct=duration>0 and math.max(0,math.min(1,position/duration)) or 0
    local fill=math.floor(barW*pct+0.5)
    local bar="["..string.rep("=",fill)..string.rep("-",barW-fill).."]"
    ui.text(x+1,top+1,format_duration(position),colors.lightGray,colors.black)
    ui.text(x+7,top+1,bar,colors.white,colors.black)
    local total=format_duration(now.duration)
    ui.text(x+w-#total-1,top+1,total,colors.lightGray,colors.black)
  end

  local action=now and now.state=="paused" and "[PLAY]" or "[PAUSE]"
  local controls="|<  -10  "..action.."  +10  >|  V- V+  R:"..
    tostring(state.repeat_mode):upper().."  S:"..(state.shuffle and "ON" or "OFF")
  ui.text(x+1,top+2,fit(controls,math.max(1,w-2)),colors.white,colors.black)

  local queue=("Queue %d/%d  Vol %d%%"):format(
    tonumber(state.queue_index) or 0,tonumber(state.queue_count) or 0,
    math.floor((tonumber(state.volume) or 0)*100+0.5))
  ui.text(x+1,top+3,fit(queue,math.max(1,w-2)),colors.lightGray,colors.black)
  ui.text(x+1,top+4,fit("Space play/pause | <-/-> seek | N/P track | -/+ volume | Q repeat | S shuffle",math.max(1,w-2)),colors.gray,colors.black)
end

local function direct_download(st)
  local url=tostring(st.input or "")
  if not url:match("^https?://") then
    st.message="Paste an authorized direct .dfpwm URL"
    return
  end
  if not url:lower():match("%.dfpwm[%?%#]?.*$") then
    st.message="Direct downloads must be .dfpwm audio"
    return
  end

  local name=tostring(st.direct_name or "download.dfpwm")
  if name=="download.dfpwm" then
    local fromUrl=url:match("/([^/%?%#]+)[%?%#]?.*$")
    if fromUrl and fromUrl:lower():match("%.dfpwm$") then name=fromUrl end
  end
  name=name:gsub("[^%w%._%- ]","_")
  if not name:lower():match("%.dfpwm$") then name=name..".dfpwm" end
  local root=Music.root():gsub("^/","")
  local final=fs.combine(root,name)
  local temp=final..".part"

  local h,err=http.get(url,nil,true)
  if not h then st.message=tostring(err or "download failed");return end
  local code=h.getResponseCode and h.getResponseCode() or 200
  if tonumber(code)~=200 then
    h.close()
    st.message="HTTP "..tostring(code)
    return
  end

  local out=fs.open(temp,"wb")
  if not out then h.close();st.message="cannot open music cache";return end
  local total=0
  while true do
    local chunk=h.read(16*1024)
    if not chunk then break end
    local free=fs.getFreeSpace and fs.getFreeSpace(root) or math.huge
    if free~="unlimited" and tonumber(free) and tonumber(free)<#chunk+65536 then
      h.close();out.close();fs.delete(temp)
      st.message="not enough CC disk space"
      return
    end
    out.write(chunk)
    total=total+#chunk
  end
  h.close();out.close()
  if fs.exists(final) then fs.delete(final) end
  fs.move(temp,final)

  refresh(st)
  st.message=("Cached %d KB"):format(math.floor(total/1024))
end

local function resolve_spotify(st)
  local data,err=Music.spotify_oembed(st.input)
  if not data then
    st.spotify=nil;st.match=nil;st.message=tostring(err)
    return
  end
  st.spotify=data
  refresh(st)
  local match,score=Music.find_best(data.title or "",st.tracks)
  st.match=match
  st.message=match and ("Local match "..tostring(score).." pts") or "Metadata resolved; no local match"
end

function M.draw(ctx,st,ui,x,y,w,h)
  ui.fill(x,y,x+w-1,y+h-1,colors.black,colors.white)
  draw_tabs(st,ui,x,y)

  if st.tab==1 then
    local tracks=st.tracks or {}
    local now=Music.now_playing()

    ui.text(x+1,y+1,"TITLE / ARTIST                     TIME",colors.gray,colors.black)
    local body=math.max(1,h-8)
    if st.selected<st.scroll then st.scroll=st.selected end
    if st.selected>=st.scroll+body then st.scroll=st.selected-body+1 end

    for row=1,body do
      local idx=st.scroll+row-1
      local t=tracks[idx]
      local yy=y+1+row
      ui.fill(x,yy,x+w-1,yy,colors.black,colors.white)
      if t then
        local active=now and (
          (t.id and now.track_id and tostring(t.id)==tostring(now.track_id))
          or (t.path and now.path==t.path)
        )
        local bg=idx==st.selected and colors.lightGray or colors.black
        local fg=idx==st.selected and colors.black or (active and colors.lime or colors.white)
        ui.fill(x,yy,x+w-1,yy,bg,fg)
        local label=(active and "> " or "  ")..
          tostring(t.artist~="" and (t.artist.." - "..t.title) or t.title)
        local line=fit(label,math.max(8,w-8))
        ui.text(x+1,yy,line,fg,bg)
        local dur=format_duration(t.duration)
        ui.text(x+w-#dur-1,yy,dur,fg,bg)
      end
    end
    if #tracks==0 then
      ui.text(x+2,y+4,"No music available yet.",colors.gray,colors.black)
      ui.text(x+2,y+5,st.bridge_error and "Harmoni bridge is offline." or "Bridge library is still converting.",colors.gray,colors.black)
    end
    draw_transport(ctx,st,ui,x,y,w,h)

  elseif st.tab==2 then
    ui.text(x+1,y+2,"Spotify link resolver",colors.orange,colors.black)
    ui.fill(x+1,y+4,x+w-2,y+4,colors.gray,colors.white)
    local shown=st.input=="" and "Paste Spotify track link..." or st.input
    ui.text(x+2,y+4,fit(shown,math.max(1,w-4)),
      st.input=="" and colors.lightGray or colors.white,colors.gray)

    if st.spotify then
      ui.text(x+1,y+6,"Spotify",colors.gray,colors.black)
      ui.text(x+11,y+6,fit(st.spotify.title or "-",math.max(1,w-12)),colors.white,colors.black)
      if st.match then
        ui.text(x+1,y+8,"Local match",colors.lime,colors.black)
        ui.text(x+1,y+9,fit((st.match.artist~="" and st.match.artist.." - " or "")..st.match.title,w-2),colors.white,colors.black)
        ui.text(x+1,y+11,"P  Play matched cached track",colors.lightGray,colors.black)
      else
        ui.text(x+1,y+8,"Not in local library.",colors.yellow,colors.black)
        ui.text(x+1,y+9,"Import an owned copy, then resolve again.",colors.gray,colors.black)
      end
    end
    ui.text(x+1,y+h-2,"Enter resolve | U clear | paste supported",colors.gray,colors.black)

  else
    ui.text(x+1,y+2,"Authorized direct DFPWM cache",colors.orange,colors.black)
    ui.fill(x+1,y+4,x+w-2,y+4,colors.gray,colors.white)
    local shown=st.input=="" and "Paste direct .dfpwm URL..." or st.input
    ui.text(x+2,y+4,fit(shown,math.max(1,w-4)),
      st.input=="" and colors.lightGray or colors.white,colors.gray)
    ui.text(x+1,y+6,"Save as: "..fit(st.direct_name,math.max(1,w-11)),colors.white,colors.black)
    ui.text(x+1,y+8,"Enter downloads to /home/caden/Music",colors.lightGray,colors.black)
    ui.text(x+1,y+9,"Only use audio you may download.",colors.gray,colors.black)
    ui.text(x+1,y+h-2,"Enter cache | U clear",colors.gray,colors.black)
  end

  ui.fill(x,y+h-1,x+w-1,y+h-1,colors.gray,colors.white)
  local now=Music.now_playing()
  local footer=st.message or (now and ("Playing: "..tostring(now.title)) or
    (#(st.tracks or {}).." cached track(s)"))
  ui.text(x+1,y+h-1,fit(footer,math.max(1,w-2)),
    st.message and colors.orange or (now and colors.lime or colors.lightGray),colors.gray)
end

function M.event(ctx,st,ev,a,b,c,rx,ry,w,h)
  if ev=="key" then
    if a==keys.tab then
      st.tab=st.tab%#tabs+1
      st.input=""
      st.message=nil
      return true
    elseif a==keys.up and st.tab==1 then
      st.selected=math.max(1,st.selected-1);return true
    elseif a==keys.down and st.tab==1 then
      st.selected=math.min(math.max(1,#(st.tracks or {})),st.selected+1);return true
    elseif a==keys.space and st.tab==1 then
      local now=Music.now_playing()
      local r,err
      if now then r,err=Music.toggle_pause(ctx)
      else r,err=play_selected(ctx,st) end
      st.message=r and (r.state=="paused" and "Playback paused" or "Playback resumed") or tostring(err)
      return true
    elseif a==keys.left and st.tab==1 then
      local r,err=Music.seek_relative(ctx,-10)
      st.message=r and ("Seek "..format_duration(r.position)) or tostring(err)
      return true
    elseif a==keys.right and st.tab==1 then
      local r,err=Music.seek_relative(ctx,10)
      st.message=r and ("Seek "..format_duration(r.position)) or tostring(err)
      return true
    elseif a==keys.n and st.tab==1 then
      local r,err=Music.next(ctx);st.message=r and ("Next: "..tostring(r.title)) or tostring(err);return true
    elseif a==keys.p and st.tab==1 then
      local r,err=Music.previous(ctx);st.message=r and ("Previous: "..tostring(r.title)) or tostring(err);return true
    elseif a==keys.q and st.tab==1 then
      st.message="Repeat "..Music.cycle_repeat();return true
    elseif a==keys.s and st.tab==1 then
      st.message="Shuffle "..(Music.toggle_shuffle() and "on" or "off");return true
    elseif a==keys.r and st.tab==1 then
      refresh(st);st.message="Library rescanned";return true
    elseif a==keys.x and st.tab==1 then
      Music.stop(ctx);st.message="Playback stopped";return true
    elseif a==keys.enter then
      if st.tab==1 then
        local t=selected(st)
        if t then
          local r,err=play_selected(ctx,st,t)
          st.message=r and ("Playing on "..tostring(r.speaker).." ["..tostring(r.format or "audio").."]") or tostring(err)
        end
      elseif st.tab==2 then
        resolve_spotify(st)
      else
        direct_download(st)
      end
      return true
    elseif st.tab==2 and a==keys.p and st.match then
      local r,err=Music.play_track(ctx,st.match,nil,1)
      st.message=r and ("Playing local match on "..tostring(r.speaker)) or tostring(err)
      return true
    elseif (st.tab==2 or st.tab==3) and a==keys.backspace then
      st.input=st.input:sub(1,-2);return true
    elseif (st.tab==2 or st.tab==3) and a==keys.u then
      st.input="";st.spotify=nil;st.match=nil;st.message="Input cleared";return true
    end

  elseif ev=="char" and st.tab==1 then
    if a=="-" then
      local v=Music.adjust_volume(-0.05);st.message=("Volume %d%%"):format(math.floor(v*100+0.5));return true
    elseif a=="+" or a=="=" then
      local v=Music.adjust_volume(0.05);st.message=("Volume %d%%"):format(math.floor(v*100+0.5));return true
    end

  elseif ev=="char" and (st.tab==2 or st.tab==3) then
    st.input=st.input..tostring(a or "")
    return true

  elseif ev=="paste" and (st.tab==2 or st.tab==3) then
    st.input=st.input..tostring(a or "")
    return true

  elseif ev=="mouse_click" and rx and ry then
    if ry==1 then
      if rx<12 then st.tab=1
      elseif rx<24 then st.tab=2
      else st.tab=3 end
      st.input="";st.message=nil
      return true
    elseif st.tab==1 and ry==h-4 then
      local now=Music.now_playing()
      if now and tonumber(now.duration) and tonumber(now.duration)>0 then
        local left=8
        local right=math.max(left+1,w-10)
        local pct=math.max(0,math.min(1,(rx-left)/(right-left)))
        local r,err=Music.seek(ctx,tonumber(now.duration)*pct)
        st.message=r and ("Seek "..format_duration(r.position)) or tostring(err)
        return true
      end
    elseif st.tab==1 and ry==h-3 then
      local r,err
      if rx<=4 then r,err=Music.previous(ctx)
      elseif rx<=9 then r,err=Music.seek_relative(ctx,-10)
      elseif rx<=18 then
        if Music.now_playing() then r,err=Music.toggle_pause(ctx) else r,err=play_selected(ctx,st) end
      elseif rx<=23 then r,err=Music.seek_relative(ctx,10)
      elseif rx<=27 then r,err=Music.next(ctx)
      elseif rx<=31 then
        local v=Music.adjust_volume(-0.05);st.message=("Volume %d%%"):format(math.floor(v*100+0.5));return true
      elseif rx<=35 then
        local v=Music.adjust_volume(0.05);st.message=("Volume %d%%"):format(math.floor(v*100+0.5));return true
      elseif rx<=44 then
        st.message="Repeat "..Music.cycle_repeat();return true
      else
        st.message="Shuffle "..(Music.toggle_shuffle() and "on" or "off");return true
      end
      st.message=r and "Playback updated" or tostring(err)
      return true
    elseif st.tab==1 and ry>=3 and ry<=h-6 then
      local idx=st.scroll+ry-3
      if (st.tracks or {})[idx] then st.selected=idx;return true end
    end

  elseif ev=="mouse_scroll" and st.tab==1 then
    st.selected=math.max(1,math.min(math.max(1,#(st.tracks or {})),st.selected+(tonumber(a) or 0)))
    return true
  end

  return false
end

return M
