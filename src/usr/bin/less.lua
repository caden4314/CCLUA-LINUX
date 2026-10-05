local function resolve(ctx,path)
  path=tostring(path or "")
  if path=="" then return nil end
  if path:sub(1,1)~="/" then
    path=ctx.kernel.vfs.normalize(ctx.process.cwd.."/"..path)
  end
  return path
end

local function load_lines(ctx,path)
  local h,err=ctx.kernel.vfs.open(path,"r")
  if not h then return nil,err end
  local lines={}
  while true do
    local line=h.readLine and h.readLine() or nil
    if line==nil then break end
    lines[#lines+1]=line
  end
  if h.close then h.close() end
  return lines
end

local function draw(lines,top,path,message)
  local w,h=term.getSize()
  local page=math.max(1,h-1)
  term.clear()
  term.setCursorPos(1,1)
  for row=0,page-1 do
    local line=lines[top+row]
    if not line then break end
    term.setCursorPos(1,row+1)
    term.setTextColor(colors.white)
    write(tostring(line):sub(1,w))
  end

  local finish=math.min(#lines,top+page-1)
  local percent=#lines==0 and 100 or math.floor((finish/#lines)*100)
  local status=message or ("%s  lines %d-%d/%d  %d%%  q quit  / search"):format(
    path,top,finish,#lines,percent
  )
  term.setCursorPos(1,h)
  term.setBackgroundColor(colors.lightGray)
  term.setTextColor(colors.black)
  write(status:sub(1,w)..string.rep(" ",math.max(0,w-#status)))
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  return page
end

local function search(lines,needle,start)
  needle=tostring(needle or ""):lower()
  if needle=="" then return nil end
  for i=math.max(1,start or 1),#lines do
    if tostring(lines[i]):lower():find(needle,1,true) then return i end
  end
end
return {main=function(ctx,args)
  local file=resolve(ctx,args and args[1])
  if not file then print("less: missing file operand");return 1 end
  local lines,err=load_lines(ctx,file)
  if not lines then print("less: "..tostring(err));return 1 end

  if ctx.pty then ctx.pty:set_alternate_screen(true) end
  local top=1
  local message=nil

  while true do
    local page=draw(lines,top,file,message)
    message=nil
    local ev,a=coroutine.yield("wait_event",{"char","key","term_resize"})

    if ev=="char" then
      local ch=tostring(a or "")
      if ch=="q" then break
      elseif ch==" " then top=math.min(math.max(1,#lines-page+1),top+page)
      elseif ch=="g" then top=1
      elseif ch=="G" then top=math.max(1,#lines-page+1)
      elseif ch=="/" then
        local _,h=term.getSize()
        term.setCursorPos(1,h)
        term.clearLine()
        term.setTextColor(colors.yellow)
        write("/")
        term.setTextColor(colors.white)
        local needle=read()
        local found=search(lines,needle,top+1) or search(lines,needle,1)
        if found then
          top=math.min(found,math.max(1,#lines-page+1))
        else
          message="Pattern not found: "..tostring(needle or "")
        end
      end
    elseif ev=="key" then
      if a==keys.up then top=math.max(1,top-1)
      elseif a==keys.down then top=math.min(math.max(1,#lines-page+1),top+1)
      elseif keys.pageUp and a==keys.pageUp then top=math.max(1,top-page)
      elseif keys.pageDown and a==keys.pageDown then
        top=math.min(math.max(1,#lines-page+1),top+page)
      elseif a==keys.home then top=1
      elseif a==keys["end"] then top=math.max(1,#lines-page+1)
      end
    end
  end

  if ctx.pty then ctx.pty:set_alternate_screen(false) end
  return 0
end}
