from pathlib import Path
from lupa import LuaRuntime

ROOT=Path(r"E:\Minecraft\CCLUA-LINUX")
lua=LuaRuntime(unpack_returned_tuples=True)
g=lua.globals()
g.py_read=lambda p:(ROOT/"src"/str(p).lstrip("/").replace("/", "\\")).read_text(encoding="utf-8")

lua.execute(r'''
colors={black=1,white=2}
function dofile(path)
  local code=py_read(path)
  local fn,err=load(code,"@"..path,"t",_G)
  if not fn then error(err) end
  return fn()
end

function mock_monitor(blockW,blockH)
  local current=0.5
  local setCalls=0
  local m={}
  function m.setTextScale(s) current=s;setCalls=setCalls+1 end
  function m.getTextScale() return current end
  function m.getSetScaleCalls() return setCalls end
  function m.getSize()
    -- Match CC:Tweaked ServerMonitor.rebuild with CCPerf's 2x density:
    -- physical monitor span minus the 5/16 block bezel, divided by the
    -- effective 3x4.5 pixel character cell and text scale.
    local w=(blockW-0.3125)/(current*3.0*0.015625)
    local h=(blockH-0.3125)/(current*4.5*0.015625)
    return math.max(1,math.floor(w+0.5)),
           math.max(1,math.floor(h+0.5))
  end
  function m.setCursorBlink(_) end
  function m.setBackgroundColor(_) end
  function m.setTextColor(_) end
  return m
end

layout=dofile("/usr/lib/cclua/monitor_layout.lua")

local wall=mock_monitor(4,3)
local scale,w,h,fits=layout.fit(wall,{min_width=46,min_height=18,max_scale=3})
assert(scale==1.0,("expected 1.0 got %s (%sx%s)"):format(scale,w,h))
assert(fits and w>=70 and h>=30)
assert(wall.getSetScaleCalls()==1,"initial fit should resize once")
local calls=wall.getSetScaleCalls()
local scaleAgain=layout.fit(wall,{min_width=46,min_height=18,max_scale=3})
assert(scaleAgain==1.0 and wall.getSetScaleCalls()==calls,
  "stable fit must not call setTextScale again")

local cinema=mock_monitor(16,9)
local s2,w2,h2,f2=layout.fit(cinema,{min_width=70,min_height=24,max_scale=3})
assert(s2==2.0,("16x9 wall should use scale 2.0, got %s"):format(s2))
assert(f2 and w2>=160 and w2<=175 and h2>=58 and h2<=66,
  ("16x9 wall expected ~167x62 workspace, got %sx%s"):format(w2,h2))

local fixed=mock_monitor(1,1)
local s3=layout.fit(fixed,{min_width=100,min_height=30,fixed_scale=0.5})
assert(s3==0.5)

print("MONITOR_LAYOUT_OK")
print("STANDARD_WALL_SCALE",scale,w,h)
print("WALL_16X9_SCALE",s2,w2,h2)
''')
