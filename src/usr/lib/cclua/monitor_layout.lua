local M={}

local SCALES={5.0,4.5,4.0,3.5,3.0,2.5,2.0,1.5,1.0,0.5}

local function clamp_scale(v)
  v=tonumber(v) or 0.5
  v=math.max(0.5,math.min(5.0,v))
  return math.floor(v*2+0.5)/2
end

local function monitor_state(mon)
  local okScale,scale=pcall(mon.getTextScale)
  local okSize,w,h=pcall(mon.getSize)
  if not okSize then return nil,nil,nil end
  if not okScale then scale=nil end
  return tonumber(scale),tonumber(w) or 0,tonumber(h) or 0
end

local function set_scale(mon,scale,current)
  if current and math.abs(current-scale)<0.001 then
    local _,w,h=monitor_state(mon)
    return w,h
  end
  local ok=pcall(mon.setTextScale,scale)
  if not ok then return nil end
  local _,w,h=monitor_state(mon)
  return w,h
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

  local currentScale,currentW,currentH=monitor_state(mon)
  if not currentW then return 0.5,0,0,false end
  currentScale=clamp_scale(currentScale or 0.5)

  if fixed~=nil then
    local scale=clamp_scale(fixed)
    local w,h=set_scale(mon,scale,currentScale)
    return scale,w or 0,h or 0,(w and w>=minW and h>=minH) or false
  end

  local requestedMax=clamp_scale(opts.max_scale or 5)
  local autoCeiling=clamp_scale(opts.auto_max_scale or 1.0)
  local maxScale=math.min(requestedMax,autoCeiling)
  local minScale=clamp_scale(opts.min_scale or 0.5)
  local baseW=currentW*currentScale
  local baseH=currentH*currentScale
  local target=minScale

  -- Predict the largest fitting scale from the current monitor geometry.
  -- Auto mode intentionally caps at 1.0 so CCPerf's 2x backing density remains
  -- useful on large walls instead of blowing dashboards up to 1.5-3.0 text.
  -- Fixed mode above may still explicitly request a larger scale.
  -- This also avoids probing every scale with setTextScale(), which emits
  -- monitor_resize and can create a resize/flicker feedback loop.
  for _,scale in ipairs(SCALES) do
    if scale<=maxScale and scale>=minScale then
      local pw=math.floor(baseW/scale+0.001)
      local ph=math.floor(baseH/scale+0.001)
      if pw>=minW and ph>=minH then
        target=scale
        break
      end
    end
  end

  local w,h=set_scale(mon,target,currentScale)
  if not w then return target,0,0,false end
  if w>=minW and h>=minH then return target,w,h,true end

  -- Only compensate for an integer-rounding miss. This should be at most one
  -- extra resize and, unlike the old probing loop, converges immediately.
  while target>minScale do
    local previous=target
    target=math.max(minScale,target-0.5)
    w,h=set_scale(mon,target,previous)
    if w and w>=minW and h>=minH then return target,w,h,true end
  end
  return target,w or 0,h or 0,false
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
