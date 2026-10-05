local M={}
local next_id=1

local function wake(id)
  if os.queueEvent then os.queueEvent("cclua_stream_"..tostring(id)) end
end

function M.pipe()
  local id=next_id
  next_id=next_id+1
  local state={id=id,chunks={},closed=false,writers=1,bytes=0}

  local reader={kind="pipe-reader",id=id}
  function reader:readAll()
    local out={}
    while true do
      while #state.chunks>0 do
        local s=table.remove(state.chunks,1)
        state.bytes=math.max(0,state.bytes-#s)
        out[#out+1]=s
      end
      if state.closed then return table.concat(out) end
      coroutine.yield("wait_event","cclua_stream_"..id)
    end
  end
  function reader:readLine()
    reader._buffer=reader._buffer or ""
    while true do
      local p=reader._buffer:find("\n",1,true)
      if p then
        local line=reader._buffer:sub(1,p-1)
        reader._buffer=reader._buffer:sub(p+1)
        return line
      end
      if #state.chunks>0 then
        local s=table.remove(state.chunks,1)
        state.bytes=math.max(0,state.bytes-#s)
        reader._buffer=reader._buffer..s
      elseif state.closed then
        if reader._buffer=="" then return nil end
        local line=reader._buffer
        reader._buffer=""
        return line
      else
        coroutine.yield("wait_event","cclua_stream_"..id)
      end
    end
  end
  function reader:close() reader.closed=true end

  local writer={kind="pipe-writer",id=id}
  function writer:write(s)
    if state.closed then return nil,"EPIPE" end
    s=tostring(s or "")
    if s~="" then
      state.chunks[#state.chunks+1]=s
      state.bytes=state.bytes+#s
      wake(id)
    end
    return true
  end
  function writer:close()
    if writer.closed then return true end
    writer.closed=true
    state.writers=math.max(0,state.writers-1)
    if state.writers==0 then state.closed=true;wake(id) end
    return true
  end

  return reader,writer,state
end

function M.file_reader(kernel,path)
  local h,err=kernel.vfs.open(path,"r")
  if not h then return nil,err end
  local closed=false
  return {
    kind="file-reader",
    readAll=function() return h.readAll and h.readAll() or "" end,
    readLine=function() return h.readLine and h.readLine() or nil end,
    close=function()
      if closed then return end
      closed=true
      if h.close then h.close() end
    end,
  }
end

function M.file_writer(kernel,path,append)
  local h,err=kernel.vfs.open(path,append and "a" or "w")
  if not h then return nil,err end
  local closed=false
  return {
    kind="file-writer",
    write=function(_,s)
      if closed then return nil,"EBADF" end
      h.write(tostring(s or ""));return true
    end,
    close=function()
      if closed then return end
      closed=true
      if h.close then h.close() end
    end,
  }
end

function M.terminal(output,base)
  local t={fg=(colors and colors.white) or 1,bg=(colors and colors.black) or 32768,x=1,y=1}
  local function size()
    if base and base.getSize then return base.getSize() end
    return 80,24
  end
  function t.write(s)
    s=tostring(s or "")
    local ok,err=output:write(s)
    if ok then
      local last=s:match("([^\n]*)$") or ""
      local n=select(2,s:gsub("\n",""))
      if n>0 then t.y=t.y+n;t.x=#last+1 else t.x=t.x+#s end
    end
    return ok,err
  end
  function t.blit(s,fg,bg) return t.write(s) end
  function t.clear() end
  function t.clearLine() end
  function t.getCursorPos() return t.x,t.y end
  function t.setCursorPos(x,y) t.x=tonumber(x) or 1;t.y=tonumber(y) or 1 end
  function t.setCursorBlink() end
  function t.getCursorBlink() return false end
  function t.getSize() return size() end
  function t.scroll() end
  function t.isColor() return true end
  t.isColour=t.isColor
  function t.setTextColor(c) t.fg=c end
  t.setTextColour=t.setTextColor
  function t.getTextColor() return t.fg end
  t.getTextColour=t.getTextColor
  function t.setBackgroundColor(c) t.bg=c end
  t.setBackgroundColour=t.setBackgroundColor
  function t.getBackgroundColor() return t.bg end
  t.getBackgroundColour=t.getBackgroundColor
  function t.setPaletteColor() end
  t.setPaletteColour=t.setPaletteColor
  function t.getPaletteColor(c)
    if base and base.getPaletteColor then return base.getPaletteColor(c) end
    return 1,1,1
  end
  t.getPaletteColour=t.getPaletteColor
  return t
end

function M.terminal_writer(target)
  return {
    kind="terminal-writer",
    write=function(_,s)
      if target and target.write then target.write(tostring(s or "")) end
      return true
    end,
    close=function() end,
  }
end

function M.null_writer()
  return {kind="null",write=function() return true end,close=function() end}
end

return M
