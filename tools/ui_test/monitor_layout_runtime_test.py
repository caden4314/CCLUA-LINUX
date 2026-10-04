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
    -- Model the CCPerf 2x backing density. A one-monitor viewport which
    -- normally exposes about 51x19 at stock 0.5 has 102x38 at 0.5 and
    -- 51x19 at 1.0.
    return math.floor((51*blockW)/current+0.5),
           math.floor((19*blockH)/current+0.5)
  end
  function m.setCursorBlink(_) end
  function m.setBackgroundColor(_) end
  function m.setTextColor(_) end
  return m
end

layout=dofile("/usr/lib/cclua/monitor_layout.lua")

local one=mock_monitor(1,1)
local scale,w,h,fits=layout.fit(one,{min_width=46,min_height=18,max_scale=3})
assert(scale==1.0,("expected 1.0 got %s (%sx%s)"):format(scale,w,h))
assert(fits and w>=46 and h>=18)
assert(one.getSetScaleCalls()==1,"initial fit should resize once")
local calls=one.getSetScaleCalls()
local scaleAgain=layout.fit(one,{min_width=46,min_height=18,max_scale=3})
assert(scaleAgain==1.0 and one.getSetScaleCalls()==calls,
  "stable fit must not call setTextScale again")

local wall=mock_monitor(3,2)
local s2,w2,h2,f2=layout.fit(wall,{min_width=70,min_height=24,max_scale=3})
assert(s2==1.0,("large wall auto scale should cap at 1.0, got %s"):format(s2))
assert(f2 and w2>=70 and h2>=24)
assert(w2>=120,"large wall should retain useful high-resolution workspace")

local fixed=mock_monitor(1,1)
local s3=layout.fit(fixed,{min_width=100,min_height=30,fixed_scale=0.5})
assert(s3==0.5)

print("MONITOR_LAYOUT_OK")
print("ONE_BLOCK_SCALE",scale,w,h)
print("LARGE_WALL_SCALE",s2,w2,h2)
''')
