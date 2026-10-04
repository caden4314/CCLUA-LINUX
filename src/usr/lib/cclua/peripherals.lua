local M={}

local function names(kind)
  local out={}
  for _,name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name,kind) then out[#out+1]=name end
  end
  table.sort(out)
  return out
end

local function pick(kind,name)
  if name and peripheral.hasType(name,kind) then
    return peripheral.wrap(name),name
  end
  local list=names(kind)
  if #list==0 then return nil,nil end
  return peripheral.wrap(list[1]),list[1]
end

function M.list(kind)
  local out={}
  for _,name in ipairs(names(kind)) do
    local methods={}
    if peripheral.getMethods then
      local ok,m=pcall(peripheral.getMethods,name)
      if ok and type(m)=="table" then methods=m;table.sort(methods) end
    end
    out[#out+1]={name=name,type=kind,methods=methods}
  end
  return out
end

function M.printer_status(name)
  local printer,resolved=pick("printer",name)
  if not printer then return nil,"no printer available" end
  local okInk,ink=pcall(printer.getInkLevel)
  local okPaper,paper=pcall(printer.getPaperLevel)
  return {
    name=resolved,
    ink=okInk and ink or nil,
    paper=okPaper and paper or nil,
    ready=(okInk and (tonumber(ink) or 0)>0 and okPaper and (tonumber(paper) or 0)>0)
  }
end

local function wrap_line(line,width)
  local out={}
  line=tostring(line or "")
  if line=="" then return {""} end
  while #line>width do
    local cut=width
    local prefix=line:sub(1,width)
    local last=prefix:match("^.*()%s+")
    if last and last>1 then cut=last-1 end
    out[#out+1]=line:sub(1,cut):gsub("%s+$","")
    line=line:sub(cut+1):gsub("^%s+","")
  end
  out[#out+1]=line
  return out
end

local function wrap_text(text,width)
  local out={}
  text=tostring(text or ""):gsub("\r\n","\n"):gsub("\r","\n")
  for line in (text.."\n"):gmatch("(.-)\n") do
    for _,part in ipairs(wrap_line(line,width)) do out[#out+1]=part end
  end
  if #out==0 then out={""} end
  return out
end

function M.print_text(name,title,text,opts)
  opts=opts or {}
  local printer,resolved=pick("printer",name)
  if not printer then return nil,"no printer available" end

  local pages=0
  local source=tostring(text or "")
  local lineIndex=1
  local lines=nil

  while true do
    local okPage,started=pcall(printer.newPage)
    if not okPage then return nil,tostring(started) end
    if not started then
      return nil,pages==0 and "printer needs ink/paper or output space" or "printer ran out of ink/paper/output space"
    end

    local okSize,w,h=pcall(printer.getPageSize)
    if not okSize then return nil,tostring(w) end
    w=tonumber(w) or 25
    h=tonumber(h) or 21
    if not lines then lines=wrap_text(source,w) end

    pages=pages+1
    local pageTitle=tostring(title or "CCLUA Print Job")
    if #lines>h then pageTitle=pageTitle.." "..pages end
    pcall(printer.setPageTitle,pageTitle:sub(1,32))

    local row=1
    while row<=h and lineIndex<=#lines do
      printer.setCursorPos(1,row)
      printer.write((lines[lineIndex] or ""):sub(1,w))
      row=row+1
      lineIndex=lineIndex+1
    end

    local okEnd,ended=pcall(printer.endPage)
    if not okEnd then return nil,tostring(ended) end
    if not ended then return nil,"printer output tray is full" end
    if lineIndex>#lines then break end
    if opts.single_page then break end
  end

  return {name=resolved,pages=pages,lines=math.min(#lines,lineIndex-1)}
end

function M.speaker_status(name)
  local speaker,resolved=pick("speaker",name)
  if not speaker then return nil,"no speaker available" end
  return {name=resolved,ready=true,sample_rate=48000,max_chunk=128*1024}
end

function M.play_sound(name,sound,volume,pitch)
  local speaker,resolved=pick("speaker",name)
  if not speaker then return nil,"no speaker available" end
  local ok,res=pcall(speaker.playSound,tostring(sound or "minecraft:block.note_block.pling"),
    tonumber(volume) or 1,tonumber(pitch) or 1)
  if not ok then return nil,tostring(res) end
  return res==true and {name=resolved,playing=true} or nil,
    res==true and nil or "speaker is busy"
end

function M.play_note(name,instrument,volume,pitch)
  local speaker,resolved=pick("speaker",name)
  if not speaker then return nil,"no speaker available" end
  local ok,res=pcall(speaker.playNote,tostring(instrument or "pling"),
    tonumber(volume) or 1,tonumber(pitch) or 12)
  if not ok then return nil,tostring(res) end
  return res==true and {name=resolved,playing=true} or nil,
    res==true and nil or "speaker note limit reached"
end

function M.stop_audio(name)
  local speaker,resolved=pick("speaker",name)
  if not speaker then return nil,"no speaker available" end
  local ok,err=pcall(speaker.stop)
  if not ok then return nil,tostring(err) end
  return {name=resolved,stopped=true}
end

function M.play_audio(name,audio,volume)
  local speaker,resolved=pick("speaker",name)
  if not speaker then return nil,"no speaker available" end
  local ok,res=pcall(speaker.playAudio,audio,tonumber(volume) or 1)
  if not ok then return nil,tostring(res) end
  return res==true and {name=resolved,accepted=true} or nil,
    res==true and nil or "speaker audio buffer full"
end

return M
