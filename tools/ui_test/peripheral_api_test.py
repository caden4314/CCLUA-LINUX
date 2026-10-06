from pathlib import Path
from lupa import LuaRuntime

ROOT=Path(r"E:\Minecraft\CCLUA-LINUX")
lua=LuaRuntime(unpack_returned_tuples=True)
g=lua.globals()

g.py_read=lambda p:(ROOT/"src"/str(p).lstrip("/").replace("/", "\\")).read_text(encoding="utf-8")

lua.execute(r'''
mock={
  printer={ink=8,paper=8,pages=0,writes={}},
  speaker={sounds=0,notes=0,stops=0}
}
peripheral={}
function peripheral.getNames() return {"right","left"} end
function peripheral.hasType(name,kind)
  return (name=="right" and kind=="printer") or (name=="left" and kind=="speaker")
end
function peripheral.getMethods(name) return {} end
function peripheral.wrap(name)
  if name=="right" then
    return {
      getInkLevel=function() return mock.printer.ink end,
      getPaperLevel=function() return mock.printer.paper end,
      newPage=function()
        if mock.printer.ink<=0 or mock.printer.paper<=0 then return false end
        mock.printer.paper=mock.printer.paper-1
        mock.printer.ink=mock.printer.ink-1
        mock.printer.pages=mock.printer.pages+1
        return true
      end,
      getPageSize=function() return 25,21 end,
      setPageTitle=function(t) mock.printer.title=t end,
      setCursorPos=function(x,y) mock.printer.x=x;mock.printer.y=y end,
      write=function(s) table.insert(mock.printer.writes,s) end,
      endPage=function() return true end,
    }
  elseif name=="left" then
    return {
      playSound=function(...) mock.speaker.sounds=mock.speaker.sounds+1;return true end,
      playNote=function(...) mock.speaker.notes=mock.speaker.notes+1;return true end,
      playAudio=function(...) return true end,
      stop=function() mock.speaker.stops=mock.speaker.stops+1 end,
    }
  end
end
function dofile(path)
  local code=py_read(path)
  local fn,err=load(code,"@"..path,"t",_G)
  if not fn then error(err) end
  return fn()
end
''')

lua.execute(r'''
p=dofile("/usr/lib/cclua/peripherals.lua")
ps=p.printer_status("right")
assert(ps.name=="right" and ps.ink==8 and ps.paper==8 and ps.ready==true)

local body=string.rep("alpha beta gamma delta ",30)
job,err=p.print_text("right","Peripheral Test",body,{})
assert(job and job.pages>=2,err)
assert(mock.printer.pages==job.pages)

a,e=p.play_note("left","pling",1,12)
assert(a and mock.speaker.notes==1,e)
a,e=p.play_sound("left","minecraft:block.note_block.pling",1,1)
assert(a and mock.speaker.sounds==1,e)
a,e=p.stop_audio("left")
assert(a and mock.speaker.stops==1,e)

drivers=dofile("/usr/lib/cclua/drivers.lua")
local devices=drivers.scan()
assert(#devices==2)
local speaker=drivers.describe("left")
assert(speaker.driver=="cc.speaker" and speaker.class=="audio")
assert(drivers.has("left","audio.output"))
local printers=drivers.find("print.text")
assert(#printers==1 and printers[1].name=="right")
local caps,providers=drivers.capabilities()
assert(#caps>=6)
assert(providers["audio.output"][1]=="left")
assert(drivers.native().available==false)
''')

print("PERIPHERAL_API_OK")
print("PRINTED_PAGES", lua.eval("mock.printer.pages"))
print("NOTE_CALLS", lua.eval("mock.speaker.notes"))
print("SOUND_CALLS", lua.eval("mock.speaker.sounds"))
print("STOP_CALLS", lua.eval("mock.speaker.stops"))
