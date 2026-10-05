from pathlib import Path
from lupa import LuaRuntime

ROOT=Path(r"E:\Minecraft\CCLUA-LINUX")
lua=LuaRuntime(unpack_returned_tuples=True)
g=lua.globals()

def read_repo(path):
    p=ROOT/"src"/str(path).lstrip("/").replace("/", "\\")
    return p.read_text(encoding="utf-8")

g.py_read=read_repo

lua.execute(r'''
local files={
  ["home/caden/Music/Artist - Test Song.dfpwm"]="FAKEAUDIO",
  ["home/caden/Music/Artist - Test Song.json"]='{"title":"Test Song","artist":"Artist","duration":123.4}'
}
local dirs={
  ["home/caden/Music"]={"Artist - Test Song.dfpwm","Artist - Test Song.json"}
}
fs={}
function fs.exists(p) p=tostring(p):gsub("^/",""); return files[p]~=nil or dirs[p]~=nil end
function fs.isDir(p) p=tostring(p):gsub("^/",""); return dirs[p]~=nil end
function fs.makeDir(p) dirs[tostring(p):gsub("^/","")]=dirs[tostring(p):gsub("^/","")] or {} end
function fs.list(p) p=tostring(p):gsub("^/",""); return dirs[p] or {} end
function fs.getSize(p) p=tostring(p):gsub("^/",""); return #(files[p] or "") end
function fs.combine(a,b)
  a=tostring(a or ""):gsub("\\","/"):gsub("/+$","")
  b=tostring(b or ""):gsub("\\","/"):gsub("^/+","")
  if a=="" then return b end
  return a.."/"..b
end
function fs.getName(p) p=tostring(p):gsub("\\","/"); return p:match("([^/]+)$") or p end
function fs.getDir(p) p=tostring(p):gsub("\\","/"); return p:match("^(.*)/[^/]+$") or "" end
function fs.open(p,mode)
  p=tostring(p):gsub("^/","")
  if tostring(mode):sub(1,1)=="r" then
    local value=files[p]
    if value==nil then return nil end
    local done=false
    return {
      readAll=function() return value end,
      read=function(n)
        if done then return nil end
        done=true
        return value:sub(1,n)
      end,
      seek=function(whence,offset)
        done=false
        return tonumber(offset) or 0
      end,
      close=function() end
    }
  end
  return nil
end

textutils={}
function textutils.unserializeJSON(raw)
  if raw:find('"title":"Test Song"',1,true) then
    return {title="Test Song",artist="Artist",duration=123.4}
  end
  if raw:find('"Spotify Test"',1,true) then
    return {title="Spotify Test",provider_name="Spotify",type="rich"}
  end
  if raw:find('"catalog_count":1',1,true) then
    return {ok=true,catalog_count=1}
  end
  if raw:find('"bridge-track"',1,true) then
    return {
      count=1,
      tracks={{
        id="bridge-track",
        title="Bridge Song",
        artist="Bridge Artist",
        duration=210,
        bytes=123456,
        source="harmoni-bridge",
        stream_url="http://127.0.0.1:8765/v1/tracks/bridge-track.dfpwm",
        pcm_stream_url="http://127.0.0.1:8765/v1/tracks/bridge-track.pcm",
        preferred_format="pcm_s8"
      }}
    }
  end
  return {}
end
function textutils.urlEncode(s) return tostring(s):gsub(" ","%%20") end

http={}
function http.get(url,headers,binary)
  if url:find("open.spotify.com/oembed",1,true) then
    return {
      getResponseCode=function() return 200 end,
      readAll=function() return '{"title":"Spotify Test","provider_name":"Spotify","type":"rich"}' end,
      close=function() end
    }
  elseif url=="http://127.0.0.1:8765/v1/catalog" then
    return {
      getResponseCode=function() return 200 end,
      readAll=function() return '{"count":1,"tracks":[{"id":"bridge-track","title":"Bridge Song","artist":"Bridge Artist","duration":210,"bytes":123456,"source":"harmoni-bridge","stream_url":"http://127.0.0.1:8765/v1/tracks/bridge-track.dfpwm","pcm_stream_url":"http://127.0.0.1:8765/v1/tracks/bridge-track.pcm","preferred_format":"pcm_s8"}]}' end,
      close=function() end
    }
  elseif url=="http://127.0.0.1:8765/v1/health" then
    return {
      getResponseCode=function() return 200 end,
      readAll=function() return '{"ok":true,"catalog_count":1}' end,
      close=function() end
    }
  elseif url:find("http://127.0.0.1:8765/v1/tracks/bridge-track.pcm",1,true)==1 then
    local done=false
    return {
      getResponseCode=function() return 200 end,
      read=function(n)
        pcm_read_size=n
        if done then return nil end
        done=true
        return string.char(0,127,128,255)
      end,
      close=function() end
    }
  elseif url=="http://127.0.0.1:8765/v1/tracks/bridge-track.dfpwm" then
    local done=false
    return {
      getResponseCode=function() return 200 end,
      read=function(n)
        if done then return nil end
        done=true
        return "REMOTEAUDIO"
      end,
      close=function() end
    }
  end
  return nil,"not mocked"
end

speaker={stops=0,last=nil,last_volume=nil}
function speaker.stop() speaker.stops=speaker.stops+1 end
function speaker.playAudio(audio,volume)
  speaker.last=audio
  speaker.last_volume=volume
  return true
end
peripheral={}
function peripheral.hasType(name,kind) return name=="left" and kind=="speaker" end
function peripheral.wrap(name) if name=="left" then return speaker end end
function peripheral.find(kind,filter)
  if kind=="speaker" and (not filter or filter("left",speaker)) then return speaker end
end

os=os or {}
function os.epoch(_) return 123456 end
function os.queueEvent(...) end

function dofile(path)
  local code=py_read(path)
  local fn,err=load(code,"@"..path,"t",_G)
  if not fn then error(err) end
  return fn()
end

local nextPid=200
procs={}
ctx={process={pid=100,uid=1000,gid=1000,groups={},cwd="/home/caden",capabilities={}}}
ctx.kernel={
  process={
    create=function(spec)
      nextPid=nextPid+1
      local p={pid=nextPid,state="running"}
      procs[p.pid]=p
      return p
    end,
    get=function(pid) return procs[pid] end,
    exit=function(p,code,state) p.state=state or "exited";p.exit_code=code end
  },
  scheduler={add=function(self,proc,fn) proc.worker=fn end},
  log={write=function(...) end}
}

music=dofile("/usr/lib/cclua/desktop/music.lua")
''')

lua.execute(r'''
local tracks=music.scan()
assert(#tracks==1)
assert(tracks[1].title=="Test Song")
assert(tracks[1].artist=="Artist")
assert(tracks[1].duration==123.4)

local match,score=music.find_best("Artist Test Song",tracks)
assert(match and match.title=="Test Song")
assert(score>0)

local catalog,bridgeErr=music.catalog()
assert(catalog and #catalog==2,bridgeErr)
local remote=music.find_best("Bridge Artist Bridge Song",catalog)
assert(remote and remote.remote==true and remote.id=="bridge-track")

local status,statusErr=music.bridge_status()
assert(status and status.catalog_count==1,statusErr)

local meta,err=music.spotify_oembed("https://open.spotify.com/track/abc")
assert(meta and meta.title=="Spotify Test",err)

local bad,baderr=music.spotify_oembed("https://example.com/not-spotify")
assert(bad==nil and baderr)

local player,perr=music.play(ctx,tracks[1].path,nil,1,tracks[1])
assert(player and player.speaker=="left",perr)
assert(music.now_playing() and music.now_playing().title=="Test Song")
local localCo=coroutine.create(procs[player.pid].worker)
local okLocal,localYield=coroutine.resume(localCo)
assert(okLocal and localYield=="wait_event","local DFPWM worker failed before audio drain")
local okLocalDone=coroutine.resume(localCo,"speaker_audio_empty")
assert(okLocalDone and coroutine.status(localCo)=="dead")
assert(music.now_playing()==nil)

local catalog=music.catalog()
local remote=music.find_best("Bridge Song",catalog)
local remoteIndex=1
for i,t in ipairs(catalog) do if t.id=="bridge-track" then remoteIndex=i break end end
local remotePlayer,remoteErr=music.play_from_queue(ctx,catalog,remoteIndex,nil,0.8)
assert(remotePlayer and remotePlayer.remote==true,remoteErr)
assert(remotePlayer.format=="PCM 48k","bridge should prefer PCM")
assert(music.now_playing() and music.now_playing().state=="playing")

local remoteCo=coroutine.create(procs[remotePlayer.pid].worker)
local okRemote,remoteYield=coroutine.resume(remoteCo)
assert(okRemote and remoteYield=="wait_event","remote PCM worker failed before audio drain")
assert(pcm_read_size==128*1024,"PCM stream must fill CC speaker buffers")
assert(#speaker.last==4)
assert(speaker.last[1]==0 and speaker.last[2]==127 and speaker.last[3]==-128 and speaker.last[4]==-1)
assert(math.abs((speaker.last_volume or 0)-0.8)<0.001)
assert(music.now_playing().position>0)

local paused=music.pause(ctx)
assert(paused and paused.state=="paused" and paused.pid==nil)
paused.position=20
local resumed=music.resume(ctx)
assert(resumed and resumed.state=="playing" and resumed.position==20)
assert(resumed.stream_url:find("start=20.000",1,true))

local volume=music.adjust_volume(-0.15)
assert(math.abs(volume-0.65)<0.001)
assert(math.abs(music.now_playing().volume-0.65)<0.001)

local sought=music.seek_relative(ctx,10)
assert(sought and sought.position>=29.9 and sought.position<=30.1)
assert(sought.stream_url:find("start=30.000",1,true))

assert(music.cycle_repeat()=="all")
assert(music.cycle_repeat()=="one")
assert(music.cycle_repeat()=="off")
assert(music.toggle_shuffle()==true)
assert(music.toggle_shuffle()==false)

music.stop(ctx)
assert(music.now_playing()==nil)

local remote2={}
for k,v in pairs(remote) do remote2[k]=v end
remote2.id="bridge-track-2"
remote2.title="Bridge Song Two"
local first=music.play_from_queue(ctx,{remote,remote2},1,nil,0.75)
assert(first and first.title=="Bridge Song")
local second,secondErr=music.next(ctx)
assert(second and second.title=="Bridge Song Two",secondErr)
assert(music.playback_state().queue_index==2)
local previous,previousErr=music.previous(ctx)
assert(previous and previous.title=="Bridge Song",previousErr)
assert(music.playback_state().queue_index==1)
music.stop(ctx)

local localPlayer=music.play_from_queue(ctx,tracks,1,nil,0.7)
assert(localPlayer and localPlayer.format=="DFPWM 48k")
local localPaused=music.pause(ctx)
assert(localPaused and localPaused.state=="paused")
local localResume=music.resume(ctx)
assert(localResume and localResume.state=="playing")
music.stop(ctx)
''')

print("MUSIC_RUNTIME_OK")
print("PCM_SIGNED_AUDIO_PASS")
print("TRANSPORT_CONTROLS_PASS")
print("QUEUE_NAVIGATION_PASS")
print("LOCAL_DFPWM_FALLBACK_PASS")
