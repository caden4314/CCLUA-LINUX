local config=dofile("/usr/lib/cclua/config.lua")
local M={}

M.scenes={
  {id="house",label="House",level=100},
  {id="preshow",label="Pre-show",level=60},
  {id="trailers",label="Trailers",level=30},
  {id="feature",label="Feature",level=9},
  {id="blackout",label="Blackout",level=0},
}

local function machine()
  return config.machine()
end

function M.bridge_base()
  return tostring(machine().theater_bridge_base or "http://127.0.0.1:8766/v1")
end

function M.bridge_origin()
  return M.bridge_base():gsub("/v1/?$","")
end

local function get_json(url)
  if not http or not http.get then return nil,"HTTP API unavailable" end
  local h,err=http.get(url,{
    ["Accept"]="application/json",
    ["User-Agent"]="CCLUA-Theater/0.1"
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
  return get_json(M.bridge_base().."/health")
end

function M.catalog()
  -- theaterd owns bridge I/O. Desktop apps read its local cache so opening the
  -- Theater window never blocks the compositor on a network response handle.
  local cached=config.read_json("/var/lib/cclua/theater-catalog.json",nil)
  if type(cached)=="table" and type(cached.movies)=="table" then
    return cached.movies
  end
  return {},"Theater catalog is initializing"
end

function M.movie(id)
  id=tostring(id or "")
  local movies,err=M.catalog()
  if not movies then return nil,err end
  for _,item in ipairs(movies) do
    if tostring(item.id)==id then return item end
  end
  return nil,"movie not found"
end

function M.state()
  return config.read_json("/var/lib/cclua/theater-state.json",{
    schema=1,state="STARTING",scene="house",brightness=100,volume=0.85,
    position=0,hardware={}
  })
end

function M.command(op,payload)
  if not os.queueEvent then return nil,"event queue unavailable" end
  os.queueEvent("cclua_theater_command",tostring(op or ""),payload or {})
  return true
end

function M.scene(id)
  return M.command("scene",{scene=id})
end

function M.play(id)
  return M.command("play",{id=id})
end

function M.pause()
  return M.command("pause",{})
end

function M.stop()
  return M.command("stop",{})
end

function M.seek(delta)
  return M.command("seek",{delta=tonumber(delta) or 0})
end

function M.volume(value)
  return M.command("volume",{value=tonumber(value)})
end

function M.volume_delta(delta)
  return M.command("volume",{delta=tonumber(delta) or 0})
end

function M.format_time(seconds)
  seconds=math.max(0,math.floor(tonumber(seconds) or 0))
  local h=math.floor(seconds/3600)
  local m=math.floor((seconds%3600)/60)
  local s=seconds%60
  if h>0 then return ("%d:%02d:%02d"):format(h,m,s) end
  return ("%d:%02d"):format(m,s)
end

return M
