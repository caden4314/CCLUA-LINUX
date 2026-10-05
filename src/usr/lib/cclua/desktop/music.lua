local config=dofile("/usr/lib/cclua/config.lua")
local M={
  players={},
  queue={},
  queue_index=0,
  repeat_mode="off",
  shuffle=false,
  default_volume=0.85,
}
local ROOT="/home/caden/Music"
local BRIDGE_BASE="http://127.0.0.1:8765/v1"

-- CCLUA processes intentionally do not expose ComputerCraft's global require().
-- Keep the small DFPWM decoder local so music playback works in the sandboxed
-- Desktop runtime without broadening the process module-loading surface.
local function make_dfpwm_decoder()
  local floor=math.floor
  local charge,strength,previousBit=0,0,false
  local previousCharge=0
  local lowPassCharge=0
  local PREC=10
  local PREC_POW=2^PREC
  local PREC_HALF=2^(PREC-1)
  local STRENGTH_MIN=2^(PREC-8+1)

  return function(input)
    if type(input)~="string" then error("DFPWM decoder expected string",2) end
    local output={}
    local outN=0
    for i=1,#input do
      local inputByte=string.byte(input,i)
      for _=1,8 do
        local currentBit=(inputByte%2)==1
        local target=currentBit and 127 or -128
        local nextCharge=charge+floor((strength*(target-charge)+PREC_HALF)/PREC_POW)
        if nextCharge==charge and nextCharge~=target then
          nextCharge=nextCharge+(currentBit and 1 or -1)
        end

        local z=currentBit==previousBit and PREC_POW-1 or 0
        if strength~=z then strength=strength+(currentBit==previousBit and 1 or -1) end
        if strength<STRENGTH_MIN then strength=STRENGTH_MIN end
        charge=nextCharge

        local antijerk=charge
        if currentBit~=previousBit then
          antijerk=floor((charge+previousCharge+1)/2)
        end
        previousCharge,previousBit=charge,currentBit

        lowPassCharge=lowPassCharge+floor(((antijerk-lowPassCharge)*140+0x80)/256)
        outN=outN+1
        output[outN]=lowPassCharge
        inputByte=floor(inputByte/2)
      end
    end
    return output
  end
end

local function clamp(v,lo,hi)
  v=tonumber(v) or lo
  if v<lo then return lo end
  if v>hi then return hi end
  return v
end

local function pcm_s8_decode(input)
  local out={}
  for i=1,#input do
    local b=string.byte(input,i)
    out[i]=b>=128 and b-256 or b
  end
  return out
end

local function clean_path(path)
  return tostring(path or ""):gsub("^/","")
end

local function basename(path)
  local n=fs.getName(path)
  return n:gsub("%.dfpwm$","")
end

local function read_json(path)
  return config.read_json(path,nil)
end

local function sidecar(path)
  return tostring(path):gsub("%.dfpwm$",".json")
end

local function normalize(s)
  return tostring(s or ""):lower()
    :gsub("[^%w%s]"," ")
    :gsub("%s+"," ")
    :gsub("^%s+","")
    :gsub("%s+$","")
end

function M.root()
  if not fs.exists(clean_path(ROOT)) then fs.makeDir(clean_path(ROOT)) end
  return ROOT
end

function M.scan()
  M.root()
  local out={}
  local host=clean_path(ROOT)
  for _,name in ipairs(fs.list(host)) do
    local path=fs.combine(host,name)
    if not fs.isDir(path) and name:lower():sub(-6)==".dfpwm" then
      local meta=read_json("/"..sidecar(path)) or {}
      out[#out+1]={
        id="local:"..name,
        path="/"..path,
        file=name,
        title=meta.title or basename(name),
        artist=meta.artist or "",
        album=meta.album or "",
        duration=tonumber(meta.duration),
        source=meta.source or "local-cache",
        spotify_url=meta.spotify_url,
        bytes=fs.getSize(path),
        remote=false,
      }
    end
  end
  table.sort(out,function(a,b)
    local aa=normalize((a.artist or "").." "..(a.title or a.file))
    local bb=normalize((b.artist or "").." "..(b.title or b.file))
    return aa<bb
  end)
  return out
end

local function get_json(url)
  if not http or not http.get then return nil,"HTTP API unavailable" end
  local h,err=http.get(url,{
    ["Accept"]="application/json",
    ["User-Agent"]="CCLUA-Music/0.3"
  })
  if not h then return nil,tostring(err or "HTTP request failed") end
  local code=h.getResponseCode and h.getResponseCode() or 200
  local raw=h.readAll()
  h.close()
  if tonumber(code)~=200 then return nil,"HTTP "..tostring(code) end
  local ok,data=pcall(textutils.unserializeJSON,raw)
  if not ok or type(data)~="table" then return nil,"invalid JSON response" end
  return data
end

function M.bridge_status()
  return get_json(BRIDGE_BASE.."/health")
end

function M.bridge_catalog()
  local data,err=get_json(BRIDGE_BASE.."/catalog")
  if not data then return nil,err end
  local out={}
  for _,track in ipairs(data.tracks or {}) do
    out[#out+1]={
      id=tostring(track.id or ""),
      title=track.title or "Unknown",
      artist=track.artist or "",
      album=track.album or "",
      duration=tonumber(track.duration),
      bytes=tonumber(track.bytes),
      source=track.source or "harmoni-bridge",
      stream_url=track.stream_url,
      pcm_stream_url=track.pcm_stream_url,
      preferred_format=track.preferred_format,
      sample_rate=tonumber(track.sample_rate) or 48000,
      channels=tonumber(track.channels) or 1,
      remote=true,
    }
  end
  return out
end

function M.catalog()
  local out={}
  local remote,remoteErr=M.bridge_catalog()
  if remote then
    for _,track in ipairs(remote) do out[#out+1]=track end
  end
  for _,track in ipairs(M.scan()) do out[#out+1]=track end
  table.sort(out,function(a,b)
    local aa=normalize((a.artist or "").." "..(a.title or a.file or ""))
    local bb=normalize((b.artist or "").." "..(b.title or b.file or ""))
    if aa==bb then return tostring(a.id or "")<tostring(b.id or "") end
    return aa<bb
  end)
  return out,remoteErr
end

function M.find_best(query,tracks)
  local q=normalize(query)
  if q=="" then return nil,0 end
  tracks=tracks or M.scan()
  local best,bestScore=nil,0

  local tokens={}
  for token in q:gmatch("%S+") do
    if #token>=2 then tokens[#tokens+1]=token end
  end

  for _,track in ipairs(tracks) do
    local hay=normalize((track.artist or "").." "..(track.title or "").." "..(track.file or ""))
    local score=0
    if hay==q then score=100 end
    if hay:find(q,1,true) then score=math.max(score,80) end
    for _,token in ipairs(tokens) do
      if hay:find(token,1,true) then score=score+8 end
    end
    if score>bestScore then best,bestScore=track,score end
  end
  return best,bestScore
end

local function spotify_url_ok(url)
  url=tostring(url or "")
  return url:match("^https://open%.spotify%.com/")~=nil
    or url:match("^https://spotify%.link/")~=nil
end

function M.spotify_oembed(url)
  if not spotify_url_ok(url) then return nil,"paste a Spotify open.spotify.com or spotify.link URL" end
  if not http or not http.get then return nil,"HTTP API unavailable" end

  local encoded=textutils.urlEncode(url)
  local handle,err=http.get("https://open.spotify.com/oembed?url="..encoded,{
    ["User-Agent"]="CCLUA-Music/0.2"
  })
  if not handle then return nil,tostring(err or "Spotify metadata request failed") end

  local code=handle.getResponseCode and handle.getResponseCode() or 200
  local raw=handle.readAll()
  handle.close()
  if tonumber(code)~=200 then return nil,"Spotify metadata HTTP "..tostring(code) end

  local ok,data=pcall(textutils.unserializeJSON,raw)
  if not ok or type(data)~="table" then return nil,"invalid Spotify metadata response" end
  return {
    url=url,
    title=data.title,
    thumbnail_url=data.thumbnail_url,
    provider_name=data.provider_name,
    type=data.type,
  }
end

local function find_speaker(name)
  if name and peripheral.hasType(name,"speaker") then
    return peripheral.wrap(name),name
  end
  local foundName=nil
  local speaker=peripheral.find("speaker",function(n)
    if not foundName then foundName=n return true end
    return false
  end)
  return speaker,foundName
end

function M.stop(ctx,speakerName)
  local function stop_player(key,player)
    if player and player.pid then
      local proc=ctx.kernel.process.get(player.pid)
      if proc and proc.state~="exited" and proc.state~="killed" and proc.state~="crashed" then
        ctx.kernel.process.exit(proc,143,"killed")
        if os.queueEvent then os.queueEvent("cclua_process_exit",proc.pid,143,"killed") end
      end
    end
    local speaker=find_speaker(player and player.speaker or key)
    if speaker and speaker.stop then pcall(speaker.stop) end
    M.players[key]=nil
  end

  if speakerName then
    local key=tostring(speakerName)
    stop_player(key,M.players[key])
  else
    local playerKeys={}
    for key in pairs(M.players) do playerKeys[#playerKeys+1]=key end
    for _,key in ipairs(playerKeys) do stop_player(key,M.players[key]) end
    local speaker=find_speaker(nil)
    if speaker and speaker.stop then pcall(speaker.stop) end
  end
  return true
end

function M.play(ctx,path,speakerName,volume,meta,opts)
  local host=clean_path(path)
  if not fs.exists(host) or fs.isDir(host) then return nil,"track file not found" end
  opts=opts or {}

  local speaker,resolved=find_speaker(speakerName)
  if not speaker then return nil,"no speaker attached" end

  local start=math.max(0,tonumber(opts.position) or 0)
  local duration=meta and tonumber(meta.duration) or nil
  if duration then start=math.min(start,math.max(0,duration-0.05)) end

  M.stop(ctx,resolved)
  local parent=ctx.process or {}
  local proc,err=ctx.kernel.process.create{
    ppid=parent.pid or 1,
    name="cclua-music-player",
    uid=parent.uid or 1000,
    gid=parent.gid or 1000,
    groups=parent.groups or {},
    cwd=parent.cwd or "/home/caden",
    capabilities=parent.capabilities or {},
    argv={"music-player",path},
  }
  if not proc then return nil,err end

  local key=tostring(resolved)
  local player={
    pid=proc.pid,
    path=path,
    track=meta,
    track_id=meta and meta.id or nil,
    title=meta and meta.title or basename(path),
    artist=meta and meta.artist or "",
    duration=duration,
    position=start,
    speaker=resolved,
    state="playing",
    volume=clamp(volume or M.default_volume,0,1),
    format="DFPWM 48k",
    sample_rate=48000,
    started=os.epoch and os.epoch("utc") or 0,
  }
  M.default_volume=player.volume
  M.players[key]=player

  ctx.kernel.scheduler:add(proc,function()
    local okRun,runErr=pcall(function()
      local decoder=make_dfpwm_decoder()
      local h=fs.open(host,"rb")
      if not h then error("unable to open "..tostring(path),0) end
      if start>0 and h.seek then
        pcall(h.seek,"set",math.floor(start*6000))
      end

      while true do
        local chunk=h.read(16*1024)
        if not chunk then break end
        local audio=decoder(chunk)
        while true do
          local current=M.players[key]
          if not current or current.pid~=proc.pid then h.close();return end
          local okPlay,accepted=pcall(speaker.playAudio,audio,current.volume)
          if not okPlay then h.close();error(accepted,0) end
          if accepted then
            current.position=(current.position or 0)+(#audio/48000)
            if current.duration then current.position=math.min(current.duration,current.position) end
            break
          end
          local ev=coroutine.yield("wait_event",{"speaker_audio_empty","terminate"})
          if ev=="terminate" then h.close();return end
        end
      end
      h.close()

      coroutine.yield("wait_event",{"speaker_audio_empty","peripheral_detach","terminate"})
    end)

    local current=M.players[key]
    local natural=current and current.pid==proc.pid
    if natural then M.players[key]=nil end
    if not okRun then
      ctx.kernel.log.write("error","music","playback failed",{
        path=path,speaker=resolved,error=tostring(runErr),position=player.position
      },proc.pid)
      return 1
    end
    if natural and M._auto_advance then M._auto_advance(ctx,resolved,player) end
    return 0
  end)

  return player
end

function M.play_remote(ctx,track,speakerName,volume,opts)
  if type(track)~="table" then return nil,"track metadata required" end
  opts=opts or {}
  local pcmUrl=tostring(track.pcm_stream_url or "")
  local dfpwmUrl=tostring(track.stream_url or "")
  local usePcm=pcmUrl:sub(1,#BRIDGE_BASE)==BRIDGE_BASE
  local url=usePcm and pcmUrl or dfpwmUrl
  if url:sub(1,#BRIDGE_BASE)~=BRIDGE_BASE then
    return nil,"refusing non-bridge stream URL"
  end

  local duration=tonumber(track.duration)
  local start=math.max(0,tonumber(opts.position) or 0)
  if duration then start=math.min(start,math.max(0,duration-0.05)) end
  if usePcm and start>0 then
    url=url..(url:find("?",1,true) and "&" or "?").."start="..("%.3f"):format(start)
  end

  local speaker,resolved=find_speaker(speakerName)
  if not speaker then return nil,"no speaker attached" end

  M.stop(ctx,resolved)
  local parent=ctx.process or {}
  local proc,err=ctx.kernel.process.create{
    ppid=parent.pid or 1,
    name="cclua-music-stream",
    uid=parent.uid or 1000,
    gid=parent.gid or 1000,
    groups=parent.groups or {},
    cwd=parent.cwd or "/home/caden",
    capabilities=parent.capabilities or {},
    argv={"music-stream",tostring(track.id or "")},
  }
  if not proc then return nil,err end

  local key=tostring(resolved)
  local player={
    pid=proc.pid,
    track=track,
    track_id=track.id,
    title=track.title or "Unknown",
    artist=track.artist or "",
    duration=duration,
    position=start,
    speaker=resolved,
    remote=true,
    stream_url=url,
    state="playing",
    volume=clamp(volume or M.default_volume,0,1),
    format=usePcm and "PCM 48k" or "DFPWM 48k",
    sample_rate=48000,
    started=os.epoch and os.epoch("utc") or 0,
  }
  M.default_volume=player.volume
  M.players[key]=player

  ctx.kernel.scheduler:add(proc,function()
    local okRun,runErr=pcall(function()
      local function submit_audio(audio,h)
        while true do
          local current=M.players[key]
          if not current or current.pid~=proc.pid then h.close();return false end
          local okPlay,accepted=pcall(speaker.playAudio,audio,current.volume)
          if not okPlay then h.close();error(accepted,0) end
          if accepted then
            current.position=(current.position or 0)+(#audio/48000)
            if current.duration then current.position=math.min(current.duration,current.position) end
            return true
          end
          local ev=coroutine.yield("wait_event",{"speaker_audio_empty","terminate"})
          if ev=="terminate" then h.close();return false end
        end
      end

      if usePcm then
        local segmentSeconds=240
        local segmentStart=start
        while true do
          local segmentUrl=pcmUrl..(pcmUrl:find("?",1,true) and "&" or "?")..
            "start="..("%.3f"):format(segmentStart)..
            "&seconds="..tostring(segmentSeconds)
          player.stream_url=segmentUrl

          local h,httpErr=http.get(segmentUrl,{
            ["Accept"]="application/octet-stream",
            ["User-Agent"]="CCLUA-Music/0.4"
          },true)
          if not h then error(tostring(httpErr or "bridge PCM stream unavailable"),0) end
          local code=h.getResponseCode and h.getResponseCode() or 200
          if tonumber(code)~=200 then
            h.close()
            error("bridge PCM HTTP "..tostring(code),0)
          end

          local samples=0
          while true do
            -- CC:Tweaked buffers one playAudio call at a time. Feed the
            -- documented maximum (128 Ki samples ~= 2.73 s) so both the
            -- server and client audio queues stay comfortably ahead of
            -- Minecraft/CC tick jitter.
            local chunk=h.read(128*1024)
            if not chunk then break end
            local audio=pcm_s8_decode(chunk)
            samples=samples+#audio
            if not submit_audio(audio,h) then return end
          end
          h.close()

          local current=M.players[key]
          if not current or current.pid~=proc.pid then return end
          if samples==0 then break end
          if current.duration and current.position>=current.duration-0.05 then break end
          if samples<(segmentSeconds*48000)-1024 then break end
          segmentStart=current.position
        end
      else
        local headers={
          ["Accept"]="audio/x-dfpwm",
          ["User-Agent"]="CCLUA-Music/0.4"
        }
        if start>0 then
          headers["Range"]="bytes="..tostring(math.floor(start*6000)).."-"
        end
        local h,httpErr=http.get(url,headers,true)
        if not h then error(tostring(httpErr or "bridge DFPWM stream unavailable"),0) end
        local code=h.getResponseCode and h.getResponseCode() or 200
        if tonumber(code)~=200 and tonumber(code)~=206 then
          h.close()
          error("bridge DFPWM HTTP "..tostring(code),0)
        end

        local decoder=make_dfpwm_decoder()
        while true do
          local chunk=h.read(16*1024)
          if not chunk then break end
          if not submit_audio(decoder(chunk),h) then return end
        end
        h.close()
      end

      coroutine.yield("wait_event",{"speaker_audio_empty","peripheral_detach","terminate"})
    end)

    local current=M.players[key]
    local natural=current and current.pid==proc.pid
    if natural then M.players[key]=nil end
    if not okRun then
      ctx.kernel.log.write("error","music","bridge playback failed",{
        id=track.id,title=track.title,speaker=resolved,error=tostring(runErr),
        format=player.format,position=player.position
      },proc.pid)
      return 1
    end
    if natural and M._auto_advance then
      M._auto_advance(ctx,resolved,player)
    end
    return 0
  end)

  return player
end

function M.play_track(ctx,track,speakerName,volume,opts)
  if type(track)~="table" then return nil,"track metadata required" end
  if track.remote or track.stream_url or track.pcm_stream_url then
    return M.play_remote(ctx,track,speakerName,volume,opts)
  end
  return M.play(ctx,track.path,speakerName,volume,track,opts)
end

function M.now_playing()
  for _,player in pairs(M.players) do return player end
  return nil
end

local function player_key(player)
  return player and tostring(player.speaker or "") or nil
end

local function halt_for_control(ctx,player)
  if not player then return false end
  if player.pid then
    local proc=ctx.kernel.process.get(player.pid)
    if proc and proc.state~="exited" and proc.state~="killed" and proc.state~="crashed" then
      ctx.kernel.process.exit(proc,143,"killed")
      if os.queueEvent then os.queueEvent("cclua_process_exit",proc.pid,143,"killed") end
    end
  end
  local speaker=find_speaker(player.speaker)
  if speaker and speaker.stop then pcall(speaker.stop) end
  player.pid=nil
  return true
end

function M.play_from_queue(ctx,tracks,index,speakerName,volume)
  M.queue={}
  for i,t in ipairs(tracks or {}) do M.queue[i]=t end
  if #M.queue==0 then return nil,"queue is empty" end
  M.queue_index=math.max(1,math.min(#M.queue,tonumber(index) or 1))
  return M.play_track(ctx,M.queue[M.queue_index],speakerName,volume)
end

local function queue_advance(ctx,step,speakerName,volume,automatic)
  local count=#M.queue
  if count==0 then return nil,"queue is empty" end

  if M.repeat_mode=="one" and automatic then
    return M.play_track(ctx,M.queue[M.queue_index],speakerName,volume,{position=0})
  end

  local idx=M.queue_index
  if M.shuffle and count>1 then
    local old=idx
    repeat idx=math.random(1,count) until idx~=old
  else
    idx=idx+(step or 1)
    if idx>count then
      if M.repeat_mode=="all" then idx=1 else return nil,"end of queue" end
    elseif idx<1 then
      if M.repeat_mode=="all" then idx=count else idx=1 end
    end
  end

  M.queue_index=idx
  return M.play_track(ctx,M.queue[idx],speakerName,volume,{position=0})
end

function M.next(ctx)
  local player=M.now_playing()
  return queue_advance(
    ctx,1,
    player and player.speaker or nil,
    player and player.volume or M.default_volume,
    false
  )
end

function M.previous(ctx)
  local player=M.now_playing()
  if player and tonumber(player.position or 0)>3 then
    return M.seek(ctx,0)
  end
  return queue_advance(
    ctx,-1,
    player and player.speaker or nil,
    player and player.volume or M.default_volume,
    false
  )
end

function M.pause(ctx)
  local player=M.now_playing()
  if not player then return nil,"nothing playing" end
  if player.state=="paused" then return player end
  halt_for_control(ctx,player)
  player.state="paused"
  M.players[player_key(player)]=player
  return player
end

function M.resume(ctx)
  local player=M.now_playing()
  if not player then return nil,"nothing paused" end
  if player.state~="paused" then return player end
  local track=player.track
  if not track then return nil,"track cannot resume" end
  return M.play_track(ctx,track,player.speaker,player.volume,{position=player.position or 0})
end

function M.toggle_pause(ctx)
  local player=M.now_playing()
  if not player then return nil,"nothing playing" end
  if player.state=="paused" then return M.resume(ctx) end
  return M.pause(ctx)
end

function M.seek(ctx,seconds)
  local player=M.now_playing()
  if not player then return nil,"nothing playing" end
  local target=math.max(0,tonumber(seconds) or 0)
  if player.duration then target=math.min(target,math.max(0,player.duration-0.05)) end
  if player.state=="paused" then
    player.position=target
    return player
  end
  if not player.track then return nil,"track cannot seek" end
  return M.play_track(ctx,player.track,player.speaker,player.volume,{position=target})
end

function M.seek_relative(ctx,delta)
  local player=M.now_playing()
  if not player then return nil,"nothing playing" end
  return M.seek(ctx,(tonumber(player.position) or 0)+(tonumber(delta) or 0))
end

function M.set_volume(volume)
  local v=clamp(volume,0,1)
  M.default_volume=v
  local player=M.now_playing()
  if player then player.volume=v end
  return v
end

function M.adjust_volume(delta)
  local player=M.now_playing()
  local current=player and player.volume or M.default_volume
  return M.set_volume(current+(tonumber(delta) or 0))
end

function M.cycle_repeat()
  if M.repeat_mode=="off" then M.repeat_mode="all"
  elseif M.repeat_mode=="all" then M.repeat_mode="one"
  else M.repeat_mode="off" end
  return M.repeat_mode
end

function M.toggle_shuffle()
  M.shuffle=not M.shuffle
  return M.shuffle
end

function M.playback_state()
  local player=M.now_playing()
  return {
    player=player,
    queue_index=M.queue_index,
    queue_count=#M.queue,
    repeat_mode=M.repeat_mode,
    shuffle=M.shuffle,
    volume=player and player.volume or M.default_volume,
  }
end

function M._auto_advance(ctx,speakerName,previous)
  local nextPlayer=queue_advance(ctx,1,speakerName,previous and previous.volume or M.default_volume,true)
  return nextPlayer
end

return M
