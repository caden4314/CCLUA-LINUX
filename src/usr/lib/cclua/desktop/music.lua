local config=dofile("/usr/lib/cclua/config.lua")
local M={players={}}
local ROOT="/home/caden/Music"

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
        path="/"..path,
        file=name,
        title=meta.title or basename(name),
        artist=meta.artist or "",
        album=meta.album or "",
        duration=tonumber(meta.duration),
        source=meta.source,
        spotify_url=meta.spotify_url,
        bytes=fs.getSize(path),
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

function M.play(ctx,path,speakerName,volume,meta)
  local host=clean_path(path)
  if not fs.exists(host) or fs.isDir(host) then return nil,"track file not found" end

  local speaker,resolved=find_speaker(speakerName)
  if not speaker then return nil,"no speaker attached" end

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
  M.players[key]={
    pid=proc.pid,path=path,title=meta and meta.title or basename(path),
    speaker=resolved,started=os.epoch and os.epoch("utc") or 0
  }

  ctx.kernel.scheduler:add(proc,function()
    local okRun,runErr=pcall(function()
      local dfpwm=require("cc.audio.dfpwm")
      local decoder=dfpwm.make_decoder()
      local h=fs.open(host,"rb")
      if not h then error("unable to open "..tostring(path),0) end

      while true do
        local chunk=h.read(16*1024)
        if not chunk then break end
        local audio=decoder(chunk)
        while true do
          local okPlay,accepted=pcall(speaker.playAudio,audio,tonumber(volume) or 1)
          if not okPlay then h.close();error(accepted,0) end
          if accepted then break end
          local ev=coroutine.yield("wait_event",{"speaker_audio_empty","terminate"})
          if ev=="terminate" then h.close();return end
        end
      end
      h.close()

      coroutine.yield("wait_event",{"speaker_audio_empty","peripheral_detach","terminate"})
    end)

    local current=M.players[key]
    if current and current.pid==proc.pid then M.players[key]=nil end
    if not okRun then
      ctx.kernel.log.write("error","music","playback failed",{
        path=path,speaker=resolved,error=tostring(runErr)
      },proc.pid)
      return 1
    end
    return 0
  end)

  return {pid=proc.pid,speaker=resolved,path=path}
end

function M.now_playing()
  for _,player in pairs(M.players) do return player end
  return nil
end

return M
