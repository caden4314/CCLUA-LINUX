local M={}

local function fit(s,w)
  s=tostring(s or "")
  if #s>w then return s:sub(1,w) end
  return s..string.rep(" ",w-#s)
end

function M.run(display,ctx,smoke)
  local w,h=display:size()
  local target=display.target
  local steps={
    {"ISO image",true,tostring(ctx.iso.meta.version or "?")},
    {"Display",display:isColor(),display.kind.." "..w.."x"..h},
    {"Data store",true,"/.cclua/data"},
    {"Peripheral bus",true,tostring(ctx.peripherals:summary().count).." device(s)"},
    {"Wireless",#ctx.peripherals:wirelessModems()>0,"auto-retry if absent"},
    {"Crypto",true,"secp256k1 + ChaCha20-Poly1305"},
  }

  target.setBackgroundColor(colors.black);target.clear()
  target.setCursorBlink(false)
  local spinner={"|","/","-","\\"}
  local progress=0
  for i,step in ipairs(steps) do
    progress=i/#steps
    target.setCursorPos(math.max(1,math.floor((w-13)/2)),math.max(2,math.floor(h/2)-4))
    target.setTextColor(colors.cyan);target.write("CCLUA-LINUX")
    target.setCursorPos(2,math.max(4,math.floor(h/2)-2)+i-1)
    target.setTextColor(step[2] and colors.lime or colors.yellow)
    target.write(step[2] and "[ OK ] " or "[WAIT] ")
    target.setTextColor(colors.white)
    target.write(fit(step[1],math.max(8,math.floor(w*.28))))
    target.setTextColor(colors.lightGray)
    target.write(" "..tostring(step[3] or ""))
    local by=math.min(h,math.max(3,h-2))
    local bw=math.max(10,w-6)
    local fill=math.floor(bw*progress)
    target.setCursorPos(4,by)
    target.setTextColor(colors.gray);target.write(string.rep("-",bw))
    target.setCursorPos(4,by)
    target.setTextColor(colors.cyan);target.write(string.rep("=",fill))
    target.setCursorPos(math.max(1,w-3),1)
    target.setTextColor(colors.lightGray);target.write(spinner[(i-1)%#spinner+1])
    if not smoke then sleep(0.08) end
  end

  target.setCursorPos(2,math.min(h,h-1))
  target.setTextColor(colors.lightGray)
  target.write("Starting kernel services...")
  if not smoke then sleep(0.12) end
  target.setBackgroundColor(colors.black);target.clear()
  return steps
end

return M
