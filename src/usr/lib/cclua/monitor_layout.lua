local M={}

local SCALES={5.0,4.5,4.0,3.5,3.0,2.5,2.0,1.5,1.0,0.5}

local function clamp_scale(v)
  v=tonumber(v) or 0.5
  v=math.max(0.5,math.min(5.0,v))
  return math.floor(v*2+0.5)/2
end

local function set_scale(mon,scale)
  local ok=pcall(mon.setTextScale,scale)
  if not ok then return nil end
  local good,w,h=pcall(mon.getSize)
  if not good then return nil end
  return tonumber(w) or 0,tonumber(h) or 0
end

-- Pick the largest (most readable) CC monitor text scale which still provides
-- the requested logical workspace. CCPerf may increase the backing terminal
-- density, but this function intentionally treats that extra density as
-- headroom rather than forcing every application to render tiny text.
function M.fit(mon,opts)
  opts=opts or {}
  local minW=math.max(1,tonumber(opts.min_width) or 40)
  local minH=math.max(1,tonumber(opts.min_height) or 18)
  local fixed=opts.fixed_scale

  if fixed~=nil then
    local scale=clamp_scale(fixed)
    local w,h=set_scale(mon,scale)
    return scale,w or 0,h or 0,(w and w>=minW and h>=minH) or false
  end

  local maxScale=clamp_scale(opts.max_scale or 5)
  local minScale=clamp_scale(opts.min_scale or 0.5)
  local best=nil

  for _,scale in ipairs(SCALES) do
    if scale<=maxScale and scale>=minScale then
      local w,h=set_scale(mon,scale)
      if w and h then
        best={scale=scale,w=w,h=h}
        if w>=minW and h>=minH then
          return scale,w,h,true
        end
      end
    end
  end

  -- Even the minimum scale could not satisfy the requested workspace. Keep
  -- the highest-resolution result we obtained so the app can enter its own
  -- compact layout rather than failing to render.
  if best then return best.scale,best.w,best.h,false end
  return 0.5,0,0,false
end

function M.configure(mon,machine,opts)
  opts=opts or {}
  machine=machine or {}
  local fixed=nil
  if tostring(machine.monitor_ui_scale_mode or "auto"):lower()=="fixed" then
    fixed=tonumber(opts.fixed_scale or machine.monitor_text_scale)
  end
  opts.fixed_scale=fixed

  local scale,w,h,fits=M.fit(mon,opts)
  pcall(mon.setCursorBlink,false)
  pcall(mon.setBackgroundColor,colors.black)
  pcall(mon.setTextColor,colors.white)
  return {
    scale=scale,width=w,height=h,fits=fits,
    min_width=opts.min_width,min_height=opts.min_height
  }
end

return M
