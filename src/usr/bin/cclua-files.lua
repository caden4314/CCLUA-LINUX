local M={}

local function host(path) return tostring(path):gsub("^/","") end
local function norm(path)
  if path=="" then return "/" end
  if path:sub(1,1)~="/" then path="/"..path end
  local out={}
  for part in path:gmatch("[^/]+") do
    if part==".." then table.remove(out)
    elseif part~="." and part~="" then out[#out+1]=part end
  end
  return "/"..table.concat(out,"/")
end

local function parent(path)
  path=norm(path)
  if path=="/" then return "/" end
  local p=path:match("^(.*)/[^/]+$") or "/"
  return p=="" and "/" or p
end

local function list(path)
  local h=host(path)
  if h=="" then h="/" end
  local ok,items=pcall(fs.list,h)
  if not ok then return {},tostring(items) end
  table.sort(items,function(a,b)
    local da=fs.isDir(fs.combine(h,a))
    local db=fs.isDir(fs.combine(h,b))
    if da~=db then return da end
    return a:lower()<b:lower()
  end)
  return items
end

local function draw(path,items,selected,offset,msg)
  local w,h=term.getSize()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()

  term.setBackgroundColor(colors.blue)
  term.setCursorPos(1,1)
  term.clearLine()
  term.setCursorPos(2,1)
  term.setTextColor(colors.white)
  write("Files")

  term.setBackgroundColor(colors.gray)
  term.setCursorPos(1,2)
  term.clearLine()
  term.setCursorPos(2,2)
  term.setTextColor(colors.white)
  write(path:sub(1,math.max(1,w-2)))

  local rows=math.max(1,h-4)
  for row=1,rows do
    local idx=offset+row-1
    local name=items[idx]
    term.setCursorPos(1,row+2)
    term.setBackgroundColor(idx==selected and colors.lightGray or colors.black)
    term.setTextColor(idx==selected and colors.black or colors.white)
    term.clearLine()
    if name then
      local full=fs.combine(host(path),name)
      local prefix=fs.isDir(full) and "[D] " or "    "
      local size=""
      if not fs.isDir(full) then
        local ok,n=pcall(fs.getSize,full)
        if ok then size=tostring(n).." B" end
      end
      local left=(prefix..name)
      if #left>w then left=left:sub(1,w) end
      term.setCursorPos(2,row+2)
      write(left:sub(1,math.max(1,w-2)))
      if size~="" and #size+2<w then
        term.setCursorPos(math.max(2,w-#size),row+2)
        write(size)
      end
    end
  end

  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.gray)
  term.setCursorPos(1,h-1)
  term.clearLine()
  term.setCursorPos(2,h-1)
  write(msg or "Up/Down select  Enter open  Backspace up  Q close")
  term.setCursorPos(1,h)
  term.clearLine()
end

function M.main(ctx,args)
  local path=norm(args[1] or ctx.process.cwd or "/home/caden")
  if not fs.exists(host(path)) or not fs.isDir(host(path)) then path="/home/caden" end
  local selected=1
  local offset=1
  local msg=nil

  while true do
    local items,err=list(path)
    if err then msg=err end
    if #items==0 then selected=1 else selected=math.max(1,math.min(selected,#items)) end
    local _,h=term.getSize()
    local rows=math.max(1,h-4)
    if selected<offset then offset=selected end
    if selected>=offset+rows then offset=selected-rows+1 end
    draw(path,items,selected,offset,msg)
    msg=nil

    local ev,a,b,c=coroutine.yield("wait_event",{"key","mouse_click","term_resize","terminate"})
    if ev=="terminate" then return 0
    elseif ev=="term_resize" then
    elseif ev=="key" then
      if a==keys.q then return 0
      elseif a==keys.up then selected=math.max(1,selected-1)
      elseif a==keys.down then selected=math.min(math.max(1,#items),selected+1)
      elseif a==keys.backspace or a==keys.left then
        path=parent(path);selected=1;offset=1
      elseif a==keys.enter or a==keys.right then
        local name=items[selected]
        if name then
          local full=norm(path.."/"..name)
          if fs.isDir(host(full)) then
            path=full;selected=1;offset=1
          else
            msg=name.."  ("..tostring(fs.getSize(host(full))).." bytes)"
          end
        end
      end
    elseif ev=="mouse_click" then
      local x,y=b,c
      if y>=3 and y<=h-2 then
        local idx=offset+(y-3)
        if items[idx] then
          if idx==selected then
            local full=norm(path.."/"..items[idx])
            if fs.isDir(host(full)) then path=full;selected=1;offset=1 end
          else selected=idx end
        end
      end
    end
  end
end

return M
