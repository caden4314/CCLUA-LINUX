local M={}
local config=dofile("/usr/lib/cclua/config.lua")
local Jobs=dofile("/usr/lib/cclua/jobs.lua")

local BUILTINS={"cd","pwd","clear","history","help","jobs","fg","bg"}

local function push(st,line,fg,bg)
  st.lines[#st.lines+1]={
    text=tostring(line or ""),
    fg=fg or colors.lightGray,
    bg=bg or colors.black,
  }
  while #st.lines>1000 do table.remove(st.lines,1) end
  st.viewOffset=0
end

local function pretty_path(path)
  path=tostring(path or "/")
  if path=="/home/caden" then return "~" end
  if path:sub(1,12)=="/home/caden/" then return "~/"..path:sub(13) end
  return path
end

local function short_path(path,maxWidth)
  path=pretty_path(path)
  if #path<=maxWidth then return path end
  if maxWidth<=5 then return path:sub(-maxWidth) end
  return "~/"..path:sub(-(maxWidth-2))
end

function M.new(ctx)
  return {
    title="Terminal",icon="T",
    cwd=ctx.process.cwd or "/home/caden",
    input="",inputPos=1,
    lines={
      {text="Ubuntu 22.04.5 LTS",fg=colors.white,bg=colors.black},
      {text="CCLUA terminal  |  help for commands  |  Tab completes",fg=colors.gray,bg=colors.black},
      {text="",fg=colors.lightGray,bg=colors.black}
    },
    history={},historyIndex=nil,historyDraft="",
    viewOffset=0,lastStatus=0,
    ctrl=false,shift=false,
    jobs=nil,foreground=nil,termW=80,termH=24,
  }
end

function M.get_title(st)
  return "Terminal - "..tostring((config.machine().hostname or "test-client"))
end

function M.snapshot(st)
  return {cwd=st.cwd}
end

function M.open(ctx,st,opts)
  if opts and opts.cwd then st.cwd=opts.cwd return true end
  return false
end

local function words(line)
  local out={}
  local buf={}
  local quote=nil
  local escape=false
  local function flush()
    if #buf>0 then out[#out+1]=table.concat(buf);buf={} end
  end
  for i=1,#line do
    local ch=line:sub(i,i)
    if escape then
      buf[#buf+1]=ch
      escape=false
    elseif ch=="\\" then
      escape=true
    elseif quote then
      if ch==quote then quote=nil else buf[#buf+1]=ch end
    elseif ch=="'" or ch=='"' then
      quote=ch
    elseif ch:match("%s") then
      flush()
    else
      buf[#buf+1]=ch
    end
  end
  flush()
  return out
end
local function add_history(st,line)
  if line=="" then return end
  if st.history[#st.history]~=line then st.history[#st.history+1]=line end
  while #st.history>200 do table.remove(st.history,1) end
  st.historyIndex=nil
  st.historyDraft=""
end

local function push_blit(st,row)
  if not row then return end
  st.lines[#st.lines+1]={
    text=tostring(row.ch or ""),
    blit_fg=tostring(row.fg or ""),
    blit_bg=tostring(row.bg or ""),
  }
  while #st.lines>1000 do table.remove(st.lines,1) end
end

local function ensure_jobs(ctx,st)
  if st.jobs then return st.jobs end
  st.jobs=Jobs.new(ctx,{
    cols=math.max(1,st.termW or 80),
    rows=math.max(1,(st.termH or 24)-1),
    notify=function()
      if os.queueEvent then os.queueEvent("cclua_pty_output",ctx.process.pid) end
    end,
  })
  return st.jobs
end

local function archive_job(st,job,final)
  if not job or not job.pty then return end
  for _,row in ipairs(job.pty:take_scrollback()) do push_blit(st,row) end
  if final and not job.archived then
    local snap=job.pty:snapshot()
    local last=0
    for y=1,#snap.screen do
      if tostring(snap.screen[y].ch or ""):match("%S") then last=y end
    end
    for y=1,last do push_blit(st,snap.screen[y]) end
    job.archived=true
  end
end

local function refresh_jobs(st)
  if not st.jobs then return end
  st.jobs:refresh()
  for _,job in ipairs(st.jobs.jobs) do
    archive_job(st,job,false)
    if st.foreground~=job and job.pty then job.pty:ack() end
    if job.done and not job.archived then
      archive_job(st,job,true)
      if st.foreground==job then
        st.foreground=nil
        st.lastStatus=job.exit_code or 1
      elseif not job.announced then
        push(st,("[%d]+ Done (%d) %s"):format(job.id,job.exit_code or 0,job.command),colors.gray)
        job.announced=true
      end
    end
  end
end

local function run_command(ctx,st,line)
  line=tostring(line or ""):gsub("^%s+",""):gsub("%s+$","")
  local argv=words(line)
  if #argv==0 then st.lastStatus=0 return 0 end

  add_history(st,line)

  local host=(config.machine().hostname or "test-client")
  local prompt="caden@"..host..":"..pretty_path(st.cwd).."$ "
  push(st,prompt..line,colors.white,colors.black)

  if argv[1]=="clear" then st.lines={};st.viewOffset=0;st.lastStatus=0;return 0 end
  if argv[1]=="pwd" then push(st,st.cwd);st.lastStatus=0;return 0 end
  if argv[1]=="cd" then
    local target=argv[2] or "/home/caden"
    if target=="~" then target="/home/caden"
    elseif target:sub(1,2)=="~/" then target="/home/caden/"..target:sub(3)
    elseif target:sub(1,1)~="/" then target=ctx.kernel.vfs.normalize(st.cwd.."/"..target) end
    target=ctx.kernel.vfs.normalize(target)
    if ctx.kernel.vfs.exists(target) and ctx.kernel.vfs.isDir(target) then
      st.cwd=target;st.lastStatus=0;return 0
    end
    push(st,"bash: cd: "..target..": No such file or directory",colors.red)
    st.lastStatus=1
    return 1
  end
  if argv[1]=="history" then
    local first=math.max(1,#st.history-49)
    for i=first,#st.history do push(st,("%4d  %s"):format(i,st.history[i])) end
    st.lastStatus=0
    return 0
  end
  if argv[1]=="help" then
    push(st,"Shell: cd pwd clear history help jobs fg bg",colors.cyan)
    push(st,"System: cclua fastfetch systemctl journalctl top ps ip ping",colors.lightGray)
    push(st,"Packages: apt dpkg  |  Legacy detail: cclua-status",colors.lightGray)
    push(st,"Jobs: append & for background  |  Ctrl+C interrupt  |  Ctrl+Z stop",colors.lightGray)
    push(st,"Editing: Left/Right Home/End  Ctrl+A/E/U/K/W/R  Tab complete",colors.lightGray)
    push(st,"Scrollback: PageUp/PageDown or mouse wheel",colors.lightGray)
    st.lastStatus=0
    return 0
  end

  local jobs=ensure_jobs(ctx,st)
  refresh_jobs(st)

  if argv[1]=="jobs" then
    for _,job in ipairs(jobs:list(true)) do
      local marker=job.foreground and "+" or "-"
      push(st,("[%d]%s %-8s %s"):format(job.id,marker,job.state,job.command),colors.lightGray)
    end
    st.lastStatus=0
    return 0
  end

  if argv[1]=="fg" then
    local job,err=jobs:foreground_job(argv[2])
    if not job then push(st,"fg: "..tostring(err),colors.red);st.lastStatus=1;return 1 end
    st.foreground=job
    st.lastStatus=0
    return 0
  end

  if argv[1]=="bg" then
    local job=jobs:get(argv[2])
    if not job then
      for i=#jobs.jobs,1,-1 do if jobs.jobs[i].state=="stopped" then job=jobs.jobs[i];break end end
    end
    local resumed,err=jobs:background_job(job)
    if not resumed then push(st,"bg: "..tostring(err),colors.red);st.lastStatus=1;return 1 end
    push(st,("[%d]+ %s &"):format(resumed.id,resumed.command),colors.gray)
    st.lastStatus=0
    return 0
  end

  local background=argv[#argv]=="&"
  if background then table.remove(argv,#argv) end
  local job,err,code=jobs:spawn(argv,{cwd=st.cwd,background=background})
  if not job then
    push(st,argv[1]..": "..tostring(err),colors.red)
    st.lastStatus=code or 1
    return st.lastStatus
  end

  if background then
    push(st,("[%d] %d"):format(job.id,job.pid),colors.gray)
    st.lastStatus=0
  else
    st.foreground=job
  end
  return 0
end
local function set_input(st,value)
  st.input=tostring(value or "")
  st.inputPos=#st.input+1
end

local function history_move(st,delta)
  if #st.history==0 then return end
  if st.historyIndex==nil then
    st.historyIndex=#st.history+1
    st.historyDraft=st.input
  end
  st.historyIndex=math.max(1,math.min(#st.history+1,st.historyIndex+delta))
  if st.historyIndex>#st.history then set_input(st,st.historyDraft)
  else set_input(st,st.history[st.historyIndex]) end
end

local function insert_input(st,text)
  text=tostring(text or ""):gsub("[\r\n]"," ")
  if text=="" then return end
  st.input=st.input:sub(1,st.inputPos-1)..text..st.input:sub(st.inputPos)
  st.inputPos=st.inputPos+#text
  st.historyIndex=nil
end

local function delete_word_left(st)
  if st.inputPos<=1 then return end
  local i=st.inputPos-1
  while i>0 and st.input:sub(i,i):match("%s") do i=i-1 end
  while i>0 and not st.input:sub(i,i):match("%s") do i=i-1 end
  st.input=st.input:sub(1,i)..st.input:sub(st.inputPos)
  st.inputPos=i+1
end

local function command_candidates(prefix)
  local seen,out={},{}
  local function add(name)
    name=tostring(name or ""):gsub("%.lua$","")
    if name:sub(1,#prefix)==prefix and not seen[name] then
      seen[name]=true;out[#out+1]=name
    end
  end
  for _,name in ipairs(BUILTINS) do add(name) end
  for _,dir in ipairs({"/bin","/usr/bin"}) do
    if fs.exists(dir) and fs.isDir(dir) then
      for _,name in ipairs(fs.list(dir)) do add(name) end
    end
  end
  table.sort(out)
  return out
end

local function resolve_path_token(st,token)
  local expanded=token
  if expanded=="~" then expanded="/home/caden"
  elseif expanded:sub(1,2)=="~/" then expanded="/home/caden/"..expanded:sub(3)
  elseif expanded:sub(1,1)~="/" then
    expanded=fs.combine(st.cwd,expanded)
  end
  return expanded
end

local function path_candidates(st,token)
  local expanded=resolve_path_token(st,token)
  local dir=fs.getDir(expanded)
  local prefix=expanded:match("([^/]+)$") or ""
  if dir=="" then dir="/" end
  if not fs.exists(dir) or not fs.isDir(dir) then return {} end

  local out={}
  for _,name in ipairs(fs.list(dir)) do
    if name:sub(1,#prefix)==prefix then
      local full=fs.combine(dir,name)
      local candidate
      local tokenDir=token:match("^(.*[/])") or ""
      candidate=tokenDir..name
      if fs.isDir(full) then candidate=candidate.."/" end
      out[#out+1]=candidate
    end
  end
  table.sort(out)
  return out
end

local function common_prefix(items)
  if #items==0 then return "" end
  local p=items[1]
  for i=2,#items do
    while p~="" and items[i]:sub(1,#p)~=p do p=p:sub(1,-2) end
  end
  return p
end

local function complete_input(st)
  local before=st.input:sub(1,st.inputPos-1)
  local tokenStart=(before:match(".*()%s") or 0)+1
  local token=before:sub(tokenStart)
  local commandPosition=before:sub(1,tokenStart-1):match("^%s*$")~=nil
  local candidates=commandPosition and command_candidates(token) or path_candidates(st,token)

  if #candidates==0 then return false end
  local replacement=#candidates==1 and candidates[1] or common_prefix(candidates)
  if #replacement>#token then
    st.input=st.input:sub(1,tokenStart-1)..replacement..st.input:sub(st.inputPos)
    st.inputPos=tokenStart+#replacement
    if #candidates==1 and replacement:sub(-1)~="/" then insert_input(st," ") end
  elseif #candidates>1 then
    push(st,table.concat(candidates,"  "),colors.lightGray)
  end
  return true
end

local function reverse_search(st)
  local needle=st.input:lower()
  for i=#st.history,1,-1 do
    local item=st.history[i]
    if needle=="" or item:lower():find(needle,1,true) then
      set_input(st,item)
      st.historyIndex=i
      return true
    end
  end
  return false
end
local function blit_color(ch)
  local n=tonumber(tostring(ch or "0"),16) or 0
  return 2^n
end

local function draw_blit_row(ui,x,y,row,maxWidth)
  local text=tostring(row and (row.ch or row.text) or ""):sub(1,maxWidth)
  local fgs=tostring(row and (row.fg or row.blit_fg) or "")
  local bgs=tostring(row and (row.bg or row.blit_bg) or "")
  if fgs=="" or bgs=="" then
    ui.text(x,y,text,colors.lightGray,colors.black)
    return
  end
  local i=1
  while i<=#text do
    local fg=fgs:sub(i,i)
    local bg=bgs:sub(i,i)
    local j=i+1
    while j<=#text and fgs:sub(j,j)==fg and bgs:sub(j,j)==bg do j=j+1 end
    ui.text(x+i-1,y,text:sub(i,j-1),blit_color(fg),blit_color(bg))
    i=j
  end
end

function M.draw(ctx,st,ui,x,y,w,h,active)
  ui.fill(x,y,x+w-1,y+h-1,colors.black,colors.white)
  st.termW=w
  st.termH=h
  local body=math.max(1,h-1)
  local contentWidth=math.max(1,w-2)

  if st.jobs then st.jobs:resize(contentWidth,body) end
  refresh_jobs(st)

  local fgjob=st.foreground
  if fgjob and not fgjob.done and fgjob.state~="stopped" then
    local snap=fgjob.pty:snapshot()
    for row=1,math.min(body,#snap.screen) do
      draw_blit_row(ui,x+1,y+row-1,snap.screen[row],contentWidth)
    end
    local status=(" [%d] %s  Ctrl+C interrupt  Ctrl+Z stop "):format(fgjob.id,fgjob.command)
    ui.text(x+1,y+h-1,status:sub(1,contentWidth),colors.black,colors.lightGray)
    if active and snap.cursor_blink then
      ui.cursor=x+math.max(1,math.min(contentWidth,snap.cursor_x))
      ui.cursor_y=y+math.max(0,math.min(body-1,snap.cursor_y-1))
    end
    fgjob.pty:ack()
    return
  end

  local last=math.max(0,#st.lines-(st.viewOffset or 0))
  local first=math.max(1,last-body+1)
  local row=0
  for i=first,last do
    row=row+1
    if row>body then break end
    local entry=st.lines[i]
    if type(entry)=="table" and entry.blit_fg then
      draw_blit_row(ui,x+1,y+row-1,entry,contentWidth)
    else
      local text=type(entry)=="table" and entry.text or tostring(entry or "")
      local fg=type(entry)=="table" and entry.fg or colors.lightGray
      local bg=type(entry)=="table" and entry.bg or colors.black
      ui.text(x+1,y+row-1,text:sub(1,contentWidth),fg,bg)
    end
  end

  if (st.viewOffset or 0)>0 and body>0 then
    local badge=(" SCROLL +%d "):format(st.viewOffset)
    ui.text(math.max(x+1,x+w-#badge-1),y,badge,colors.black,colors.yellow)
  end

  ui.fill(x,y+h-1,x+w-1,y+h-1,colors.black,colors.white)
  local host=(config.machine().hostname or "test-client")
  local user="caden"
  local maxPath=math.max(4,math.floor(w*0.34))
  local path=short_path(st.cwd,maxPath)
  local symbol=st.lastStatus==0 and "$ " or "! "
  local fixed=user.."@"..host..":"..path..symbol
  if #fixed>w-10 then fixed=symbol end

  local inputWidth=math.max(1,w-2-#fixed)
  local cursorZero=math.max(0,st.inputPos-1)
  local inputView=math.max(0,cursorZero-inputWidth+1)
  local visible=st.input:sub(inputView+1,inputView+inputWidth)

  local px=x+1
  if fixed~=symbol then
    ui.text(px,y+h-1,user,colors.lime,colors.black);px=px+#user
    ui.text(px,y+h-1,"@",colors.lightGray,colors.black);px=px+1
    ui.text(px,y+h-1,host,colors.lightBlue,colors.black);px=px+#host
    ui.text(px,y+h-1,":",colors.white,colors.black);px=px+1
    ui.text(px,y+h-1,path,colors.cyan,colors.black);px=px+#path
  end
  ui.text(px,y+h-1,symbol,st.lastStatus==0 and colors.yellow or colors.red,colors.black)
  px=px+#symbol
  ui.text(px,y+h-1,visible,colors.white,colors.black)

  if active then
    ui.cursor=px+math.max(0,math.min(inputWidth-1,cursorZero-inputView))
    ui.cursor_y=y+h-1
  end
end

function M.event(ctx,st,ev,a,b,c)
  refresh_jobs(st)

  if ev=="key" then
    if a==keys.leftCtrl or a==keys.rightCtrl then st.ctrl=true end
    if a==keys.leftShift or a==keys.rightShift then st.shift=true end
  elseif ev=="key_up" then
    if a==keys.leftCtrl or a==keys.rightCtrl then st.ctrl=false end
    if a==keys.leftShift or a==keys.rightShift then st.shift=false end
  end

  local fgjob=st.foreground
  if fgjob and not fgjob.done and fgjob.state~="stopped" then
    local jobs=ensure_jobs(ctx,st)
    if ev=="key" and st.ctrl and a==keys.c then
      fgjob.pty:write_stream("stdout","^C\n")
      jobs:signal(fgjob,"INT")
      st.lastStatus=130
      return true
    elseif ev=="key" and st.ctrl and a==keys.z then
      fgjob.pty:write_stream("stdout","^Z\n")
      jobs:stop(fgjob)
      st.foreground=nil
      push(st,("[%d]+ Stopped %s"):format(fgjob.id,fgjob.command),colors.yellow)
      return true
    elseif ev=="char" or ev=="paste" or ev=="key" or ev=="key_up"
        or ev=="mouse_click" or ev=="mouse_drag" or ev=="mouse_up" or ev=="mouse_scroll" then
      jobs:send(fgjob,{ev,a,b,c})
      return true
    end
  end

  if ev=="key_up" then return false end

  if ev=="char" then
    insert_input(st,tostring(a or ""))
    return true
  elseif ev=="paste" then
    insert_input(st,tostring(a or ""))
    return true
  end

  if ev=="mouse_scroll" then
    local delta=tonumber(a) or 0
    st.viewOffset=math.max(0,math.min(math.max(0,#st.lines-1),(st.viewOffset or 0)-delta*3))
    return true
  end

  if ev~="key" then return false end

  if a==keys.leftCtrl or a==keys.rightCtrl then return true end
  if a==keys.leftShift or a==keys.rightShift then return true end

  if st.ctrl then
    if a==keys.a then st.inputPos=1;return true
    elseif a==keys.e then st.inputPos=#st.input+1;return true
    elseif a==keys.u then
      st.input=st.input:sub(st.inputPos);st.inputPos=1;return true
    elseif a==keys.k then
      st.input=st.input:sub(1,st.inputPos-1);return true
    elseif a==keys.w then delete_word_left(st);return true
    elseif a==keys.c then
      if st.input~="" then
        push(st,"^C",colors.gray)
        st.input="";st.inputPos=1;st.lastStatus=130
      end
      return true
    elseif a==keys.r then reverse_search(st);return true
    elseif a==keys.d then
      if st.input=="" then return {action="close_self",force=true} end
    end
  end

  if a==keys.backspace then
    if st.inputPos>1 then
      st.input=st.input:sub(1,st.inputPos-2)..st.input:sub(st.inputPos)
      st.inputPos=st.inputPos-1
    end
    return true
  elseif a==keys.delete then
    if st.inputPos<=#st.input then
      st.input=st.input:sub(1,st.inputPos-1)..st.input:sub(st.inputPos+1)
    end
    return true
  elseif a==keys.enter then
    local line=st.input
    st.input="";st.inputPos=1;st.viewOffset=0
    run_command(ctx,st,line)
    return true
  elseif a==keys.up then history_move(st,-1);return true
  elseif a==keys.down then history_move(st,1);return true
  elseif a==keys.left then st.inputPos=math.max(1,st.inputPos-1);return true
  elseif a==keys.right then st.inputPos=math.min(#st.input+1,st.inputPos+1);return true
  elseif a==keys.home then st.inputPos=1;return true
  elseif a==keys["end"] then st.inputPos=#st.input+1;return true
  elseif a==keys.tab then complete_input(st);return true
  elseif keys.pageUp and a==keys.pageUp then
    st.viewOffset=math.min(math.max(0,#st.lines-1),(st.viewOffset or 0)+math.max(3,10))
    return true
  elseif keys.pageDown and a==keys.pageDown then
    st.viewOffset=math.max(0,(st.viewOffset or 0)-math.max(3,10))
    return true
  end

  return false
end

return M
