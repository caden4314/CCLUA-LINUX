local M={}

local function blit(c)
  if colors.toBlit then return colors.toBlit(c) end
  local n=0
  local v=c
  while v>1 do v=v/2;n=n+1 end
  return ("%x"):format(n)
end

function M.new(w,h)
  local c={w=w,h=h,rows={},cache={}}
  function c:reset(bg,fg)
    local bc=blit(bg or colors.black)
    local fc=blit(fg or colors.white)
    self.rows={}
    for y=1,self.h do
      self.rows[y]={
        ch=string.rep(" ",self.w),
        fg=string.rep(fc,self.w),
        bg=string.rep(bc,self.w)
      }
    end
  end
  c:reset(colors.black,colors.white)
  return c
end

local function patch(s,x,text)
  if x<1 then text=text:sub(2-x);x=1 end
  if x>#s or #text==0 then return s end
  if x+#text-1>#s then text=text:sub(1,#s-x+1) end
  return s:sub(1,x-1)..text..s:sub(x+#text)
end

function M.put(c,x,y,text,fg,bg)
  if y<1 or y>c.h or x>c.w then return end
  text=tostring(text or "")
  local start=x
  if start<1 then
    text=text:sub(2-start)
    start=1
  end
  if text=="" then return end
  local n=math.min(#text,c.w-start+1)
  if n<=0 then return end
  text=text:sub(1,n)
  local row=c.rows[y]
  row.ch=patch(row.ch,start,text)
  row.fg=patch(row.fg,start,string.rep(blit(fg or colors.white),n))
  row.bg=patch(row.bg,start,string.rep(blit(bg or colors.black),n))
end

function M.fill(c,x1,y1,x2,y2,bg,fg,ch)
  x1=math.max(1,x1);y1=math.max(1,y1)
  x2=math.min(c.w,x2);y2=math.min(c.h,y2)
  if x2<x1 or y2<y1 then return end
  local text=string.rep(ch or " ",x2-x1+1)
  for y=y1,y2 do M.put(c,x1,y,text,fg or colors.white,bg or colors.black) end
end

function M.center(c,y,text,fg,bg,x1,x2)
  x1=x1 or 1;x2=x2 or c.w
  text=tostring(text or "")
  local width=math.max(0,x2-x1+1)
  if #text>width then text=text:sub(1,width) end
  local x=x1+math.floor((width-#text)/2)
  M.put(c,x,y,text,fg,bg)
end

function M.flush(c,target,force)
  for y=1,c.h do
    local r=c.rows[y]
    local key=r.ch.."|"..r.fg.."|"..r.bg
    if force or c.cache[y]~=key then
      target.setCursorPos(1,y)
      target.blit(r.ch,r.fg,r.bg)
      c.cache[y]=key
    end
  end
end

return M
