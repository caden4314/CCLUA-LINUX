local M={}
local perfs=dofile("/usr/lib/cclua/peripherals.lua")
local Theme=dofile("/usr/lib/cclua/desktop/theme.lua")

local tabs={"Devices","Printer","Audio"}

function M.new(ctx)
  return {title="Devices",icon="Dv",tab=1,selected=1,message=nil}
end

local function device_list(ctx,tab)
  if tab==2 then return ctx.kernel.device.list("printer") end
  if tab==3 then return ctx.kernel.device.list("speaker") end
  return ctx.kernel.device.list()
end

local function clamp(st,list)
  st.selected=math.max(1,math.min(math.max(1,#list),st.selected))
end

local function status_text(dev)
  local s=dev.status or {}
  if dev.type=="printer" then
    return ("ink %s paper %s"):format(tostring(s.ink or "?"),tostring(s.paper or "?"))
  elseif dev.type=="speaker" then
    return "48 kHz HQ PCM"
  elseif dev.type=="modem" then
    return s.wireless and "wireless" or "wired"
  elseif dev.type=="monitor" then
    return ("%sx%s"):format(tostring(s.width or "?"),tostring(s.height or "?"))
  elseif dev.type=="drive" then
    return s.present and (s.label or s.audio_title or "media present") or "empty"
  end
  return dev.category or ""
end

function M.draw(ctx,st,ui,x,y,w,h)
  ui.fill(x,y,x+w-1,y+h-1,colors.black,colors.white)

  Theme.tabs(ui,x,y,w,tabs,st.tab)

  local list=device_list(ctx,st.tab)
  st._list=list
  clamp(st,list)

  if st.tab==1 then
    ui.text(x+1,y+1,"DEVICE             TYPE          STATUS",colors.gray,colors.black)
    local maxRows=math.max(1,h-3)
    for i=1,math.min(maxRows,#list) do
      local d=list[i]
      local yy=y+1+i
      local line=("%-18s %-12s %s"):format(
        tostring(d.name):sub(1,18),
        tostring(d.type or "peripheral"):sub(1,12),
        status_text(d)
      )
      Theme.list_row(ui,x,yy,w,line,i==st.selected,i==st.selected and nil or "muted")
    end

  elseif st.tab==2 then
    local d=list[st.selected]
    ui.text(x+1,y+2,"CC:Tweaked Printer",colors.orange,colors.black)
    if not d then
      ui.text(x+1,y+4,"No printer attached.",colors.red,colors.black)
    else
      local live,err=perfs.printer_status(d.name)
      if live then
        ui.text(x+1,y+4,"Device: "..d.name,colors.white,colors.black)
        ui.text(x+1,y+5,"Ink:    "..tostring(live.ink or "?"),colors.white,colors.black)
        ui.text(x+1,y+6,"Paper:  "..tostring(live.paper or "?"),colors.white,colors.black)
        ui.text(x+1,y+8,"P  Print CCLUA test page",colors.lightGray,colors.black)
      else
        ui.text(x+1,y+4,tostring(err),colors.red,colors.black)
      end
    end

  else
    local d=list[st.selected]
    ui.text(x+1,y+2,"CC:Tweaked Speaker",colors.orange,colors.black)
    if not d then
      ui.text(x+1,y+4,"No speaker attached.",colors.red,colors.black)
    else
      ui.text(x+1,y+4,"Device: "..d.name,colors.white,colors.black)
      ui.text(x+1,y+5,"Audio:  48 kHz HQ PCM transport",colors.white,colors.black)
      ui.text(x+1,y+7,"N  Play note",colors.lightGray,colors.black)
      ui.text(x+1,y+8,"S  Play test sound",colors.lightGray,colors.black)
      ui.text(x+1,y+9,"X  Stop audio",colors.lightGray,colors.black)
    end
  end

  local footer=st.message or ("Tab view  |  "..#list.." device(s)  |  Up/Down select")
  Theme.footer(ui,x,y+h-1,w,tostring(footer),st.message and "accent" or nil)
end

function M.event(ctx,st,ev,a,b,c,rx,ry,w,h)
  if ev=="key" then
    if a==keys.tab then
      st.tab=st.tab%#tabs+1
      st.selected=1
      st.message=nil
      return true
    elseif a==keys.up then
      st.selected=math.max(1,st.selected-1);return true
    elseif a==keys.down then
      st.selected=math.min(math.max(1,#(st._list or {})),st.selected+1);return true
    end

    local list=st._list or {}
    local d=list[st.selected]
    if st.tab==2 and d and a==keys.p then
      local result,err=perfs.print_text(d.name,"CCLUA Test",table.concat({
        "CCLUA Ubuntu 22.04.5",
        "Printer test page",
        "",
        "Host: "..tostring(os.getComputerLabel and os.getComputerLabel() or os.getComputerID()),
        "Printer: "..tostring(d.name),
        "Status: OK"
      },"\n"),{single_page=true})
      st.message=result and ("Printed "..tostring(result.pages).." page") or tostring(err)
      return true

    elseif st.tab==3 and d then
      if a==keys.n then
        local result,err=perfs.play_note(d.name,"pling",1,12)
        st.message=result and "Note played" or tostring(err)
        return true
      elseif a==keys.s then
        local result,err=perfs.play_sound(d.name,"minecraft:block.note_block.pling",1,1)
        st.message=result and "Sound played" or tostring(err)
        return true
      elseif a==keys.x then
        local result,err=perfs.stop_audio(d.name)
        st.message=result and "Audio stopped" or tostring(err)
        return true
      end
    end

  elseif ev=="mouse_click" and ry then
    if ry==1 then
      if rx and rx<12 then st.tab=1
      elseif rx and rx<24 then st.tab=2
      else st.tab=3 end
      st.selected=1;st.message=nil
      return true
    elseif st.tab==1 and ry>=3 and ry<h then
      local idx=ry-2
      if (st._list or {})[idx] then st.selected=idx;return true end
    end
  end
  return false
end

return M
