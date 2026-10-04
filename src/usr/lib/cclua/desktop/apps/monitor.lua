local M={}

function M.new(ctx)
  return {title="System Monitor",icon="M",tab=1,selected=1,scroll=1}
end

local function process_rows(ctx)
  local out={}
  for _,p in ipairs(ctx.kernel.process.all()) do
    out[#out+1]={
      a=tostring(p.pid or "?"),
      b=tostring(p.name or p.argv and p.argv[1] or "process"),
      c=tostring(p.state or "?"),
    }
  end
  table.sort(out,function(x,y)return tonumber(x.a) and tonumber(y.a) and tonumber(x.a)<tonumber(y.a) or x.a<y.a end)
  return out
end

local function service_rows(ctx)
  local out={}
  for _,s in ipairs(ctx.kernel.services:list()) do
    out[#out+1]={
      a=tostring(s.name or "?"),
      b=tostring(s.state or "?"),
      c=tostring(s.pid or "-"),
    }
  end
  table.sort(out,function(x,y)return x.a<y.a end)
  return out
end

local function peripheral_rows(ctx)
  local out={}
  for name,dev in pairs(ctx.kernel.device.devices or {}) do
    local t=dev.type or dev.types or "peripheral"
    if type(t)=="table" then t=table.concat(t,",") end
    out[#out+1]={a=tostring(name),b=tostring(t),c=""}
  end
  table.sort(out,function(x,y)return x.a<y.a end)
  return out
end

local function rows(ctx,tab)
  if tab==2 then return service_rows(ctx) end
  if tab==3 then return peripheral_rows(ctx) end
  return process_rows(ctx)
end

function M.draw(ctx,st,ui,x,y,w,h)
  ui.fill(x,y,x+w-1,y+h-1,colors.black,colors.white)

  local tabs={"Processes","Services","Devices"}
  local tx=x+1
  for i,label in ipairs(tabs) do
    local bg=i==st.tab and colors.gray or colors.black
    local fg=i==st.tab and colors.white or colors.lightGray
    ui.text(tx,y," "..label.." ",fg,bg)
    tx=tx+#label+3
  end

  local list=rows(ctx,st.tab)
  st._rows=list
  st.selected=math.max(1,math.min(math.max(1,#list),st.selected))
  local body=math.max(1,h-2)
  if st.selected<st.scroll then st.scroll=st.selected end
  if st.selected>=st.scroll+body then st.scroll=st.selected-body+1 end

  local header
  if st.tab==1 then header="PID   NAME                       STATE"
  elseif st.tab==2 then header="SERVICE                        STATE   PID"
  else header="DEVICE                         TYPE" end
  ui.text(x+1,y+1,header:sub(1,math.max(1,w-2)),colors.gray,colors.black)

  for line=1,body-1 do
    local idx=st.scroll+line-1
    local item=list[idx]
    local yy=y+1+line
    ui.fill(x,yy,x+w-1,yy,colors.black,colors.white)
    if item then
      local bg=idx==st.selected and colors.lightGray or colors.black
      local fg=idx==st.selected and colors.black or colors.white
      ui.fill(x,yy,x+w-1,yy,bg,fg)
      local text
      if st.tab==1 then
        text=("%-5s %-26s %s"):format(item.a,item.b:sub(1,26),item.c)
      elseif st.tab==2 then
        text=("%-30s %-7s %s"):format(item.a:sub(1,30),item.b,item.c)
      else
        text=("%-30s %s"):format(item.a:sub(1,30),item.b)
      end
      ui.text(x+1,yy,text:sub(1,math.max(1,w-2)),fg,bg)
    end
  end

  local footer=(" %d items  Tab changes view "):format(#list)
  ui.fill(x,y+h-1,x+w-1,y+h-1,colors.gray,colors.white)
  ui.text(x,y+h-1,footer:sub(1,w),colors.lightGray,colors.gray)
end

function M.event(ctx,st,ev,a,b,c,rx,ry,w,h)
  if ev=="key" then
    if a==keys.tab then st.tab=st.tab%3+1;st.selected=1;st.scroll=1;return true end
    if a==keys.up then st.selected=math.max(1,st.selected-1);return true end
    if a==keys.down then st.selected=math.min(math.max(1,#(st._rows or {})),st.selected+1);return true end
  elseif ev=="mouse_click" and ry then
    if ry==1 then
      if rx and rx<14 then st.tab=1
      elseif rx and rx<27 then st.tab=2
      else st.tab=3 end
      st.selected=1;st.scroll=1
      return true
    elseif ry>=3 and ry<h then
      local idx=st.scroll+ry-3
      if (st._rows or {})[idx] then st.selected=idx;return true end
    end
  elseif ev=="mouse_scroll" then
    st.selected=math.max(1,math.min(math.max(1,#(st._rows or {})),st.selected+(tonumber(a) or 0)))
    return true
  end
  return false
end

return M
