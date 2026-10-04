from __future__ import annotations
import json
import os
from pathlib import Path

from lupa import LuaRuntime
from PIL import Image, ImageDraw, ImageFont

REPO = Path(r"E:\Minecraft\CCLUA-LINUX")
LIVE22 = Path(r"E:\Minecraft\PrismLauncher\instances\CC Tweaked Creative\.minecraft\saves\COMPUTERS2\computercraft\computer\22")
OUT = REPO / "artifacts" / "desktop-ui"
OUT.mkdir(parents=True, exist_ok=True)

WIDTH, HEIGHT = 51, 19
CELL_W, CELL_H = 14, 24

CC_COLORS = {
    "0": (240, 240, 240), "1": (242, 178, 51), "2": (229, 127, 216),
    "3": (153, 178, 242), "4": (222, 222, 108), "5": (127, 204, 25),
    "6": (242, 178, 204), "7": (76, 76, 76), "8": (153, 153, 153),
    "9": (76, 153, 178), "a": (178, 102, 229), "b": (51, 102, 204),
    "c": (127, 102, 76), "d": (87, 166, 78), "e": (204, 76, 76),
    "f": (17, 17, 17),
}

class TerminalBuffer:
    def __init__(self, w=WIDTH, h=HEIGHT):
        self.w, self.h = w, h
        self.x, self.y = 1, 1
        self.cursor_blink = False
        self.palette = dict(CC_COLORS)
        self.clear()

    def clear(self):
        self.ch = [[" " for _ in range(self.w)] for _ in range(self.h)]
        self.fg = [["0" for _ in range(self.w)] for _ in range(self.h)]
        self.bg = [["f" for _ in range(self.w)] for _ in range(self.h)]

    def set_cursor(self, x, y):
        self.x, self.y = int(x), int(y)

    def blit(self, chars, fg, bg):
        chars, fg, bg = str(chars), str(fg), str(bg)
        for i, ch in enumerate(chars):
            xx, yy = self.x - 1 + i, self.y - 1
            if 0 <= xx < self.w and 0 <= yy < self.h:
                self.ch[yy][xx] = ch
                self.fg[yy][xx] = fg[i] if i < len(fg) else "0"
                self.bg[yy][xx] = bg[i] if i < len(bg) else "f"
        self.x += len(chars)

    def set_palette(self, color_index, r, g, b):
        nibble = f"{int(color_index).bit_length() - 1:x}"
        self.palette[nibble] = tuple(int(max(0, min(1, float(v))) * 255) for v in (r, g, b))

    def render_png(self, path: Path, title: str = ""):
        img = Image.new("RGB", (self.w * CELL_W, self.h * CELL_H), self.palette["f"])
        draw = ImageDraw.Draw(img)
        font_path = Path(r"C:\Windows\Fonts\consola.ttf")
        font = ImageFont.truetype(str(font_path), 20) if font_path.exists() else ImageFont.load_default()

        for y in range(self.h):
            for x in range(self.w):
                x0, y0 = x * CELL_W, y * CELL_H
                draw.rectangle((x0, y0, x0 + CELL_W - 1, y0 + CELL_H - 1),
                               fill=self.palette.get(self.bg[y][x], self.palette["f"]))
                ch = self.ch[y][x]
                if ch != " ":
                    draw.text((x0 + 1, y0 - 1), ch, font=font,
                              fill=self.palette.get(self.fg[y][x], self.palette["0"]))

        if title:
            draw.rectangle((0, 0, min(img.width - 1, len(title) * 8 + 8), 18), fill=(0, 0, 0))
            draw.text((4, 1), title, font=ImageFont.load_default(), fill=(255, 255, 255))
        img.save(path)

    def text_dump(self):
        return "\n".join("".join(row) for row in self.ch)

class DesktopHarness:
    def __init__(self):
        self.term = TerminalBuffer()
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.timer_id = 100
        self._install_bridge()
        self._load_desktop()

    def _lua_table(self, obj):
        if isinstance(obj, dict):
            t = self.lua.table()
            for k, v in obj.items():
                t[k] = self._lua_table(v)
            return t
        if isinstance(obj, list):
            t = self.lua.table()
            for i, v in enumerate(obj, 1):
                t[i] = self._lua_table(v)
            return t
        return obj

    def _resolve_fs(self, path):
        rel = str(path).replace("\\", "/").lstrip("/")
        return LIVE22 / Path(rel.replace("/", os.sep))

    def _read_virtual_file(self, path):
        p = str(path)
        if p.startswith("/"):
            src = REPO / "src" / p.lstrip("/")
            if src.exists():
                return src.read_text(encoding="utf-8")
        local = self._resolve_fs(p)
        if local.exists():
            return local.read_text(encoding="utf-8", errors="replace")
        raise FileNotFoundError(p)

    def _install_bridge(self):
        g = self.lua.globals()
        g.py_read = self._read_virtual_file
        g.py_set_cursor = self.term.set_cursor
        g.py_blit = self.term.blit
        g.py_palette = self.term.set_palette
        g.py_get_size = lambda: (self.term.w, self.term.h)
        g.py_exists = lambda p: self._resolve_fs(p).exists()
        g.py_is_dir = lambda p: self._resolve_fs(p).is_dir()
        g.py_list = lambda p: self._lua_table(sorted(os.listdir(self._resolve_fs(p))) if self._resolve_fs(p).is_dir() else [])
        g.py_get_size_file = lambda p: self._resolve_fs(p).stat().st_size if self._resolve_fs(p).exists() and self._resolve_fs(p).is_file() else 0
        g.py_json = lambda raw: self._lua_table(json.loads(str(raw)))
        g.py_clock = lambda: "13:05"
        g.py_computer_id = lambda: 22

        self.lua.execute(r'''
colors={
  white=1,orange=2,magenta=4,lightBlue=8,yellow=16,lime=32,pink=64,
  gray=128,lightGray=256,cyan=512,purple=1024,blue=2048,brown=4096,
  green=8192,red=16384,black=32768
}
function colors.toBlit(c)
  local n=0
  while c>1 do c=c/2;n=n+1 end
  return string.format("%x",n)
end

keys={backspace=259,tab=258,enter=257,left=263,right=262,down=264,up=265,
      q=81,t=84,leftCtrl=341,rightCtrl=345,leftAlt=342,rightAlt=346}
''')

        def next_timer(_seconds=0):
            self.timer_id += 1
            return self.timer_id
        g.py_next_timer = next_timer

        self.lua.execute(r'''
term={}
function term.getSize() return py_get_size() end
function term.setCursorPos(x,y) py_set_cursor(x,y) end
function term.blit(ch,fg,bg) py_blit(ch,fg,bg) end
function term.setCursorBlink(v) end
function term.current() return term end
function term.setPaletteColor(c,r,g,b) py_palette(c,r,g,b) end
term.setPaletteColour=term.setPaletteColor
function term.setBackgroundColor(c) end
function term.setTextColor(c) end
function term.clear() end
function term.clearLine() end

fs={}
function fs.exists(p) return py_exists(p) end
function fs.isDir(p) return py_is_dir(p) end
function fs.list(p) return py_list(p) end
function fs.getSize(p) return py_get_size_file(p) end
function fs.combine(a,b)
  a=tostring(a or ""):gsub("\\","/"):gsub("/+$","")
  b=tostring(b or ""):gsub("\\","/"):gsub("^/+","")
  if a=="" then return b end
  return a.."/"..b
end
function fs.getDir(p)
  p=tostring(p or ""):gsub("\\","/"):gsub("/+$","")
  return p:match("^(.*)/[^/]+$") or ""
end
function fs.makeDir(p) end
function fs.delete(p) end
function fs.open(p,mode)
  if tostring(mode or "r"):sub(1,1)=="r" then
    if not py_exists(p) then return nil end
    local raw=py_read(p)
    return {readAll=function() return raw end, close=function() end}
  end
  return {write=function(_) end, close=function() end}
end

textutils={}
function textutils.unserializeJSON(raw) return py_json(raw) end
function textutils.serializeJSON(_) return "{}" end
''')

        self.lua.execute(r'''
local real_os=os
os=real_os or {}
os.getComputerID=function() return py_computer_id() end
os.date=function(_) return py_clock() end
os.epoch=function(_) return 1791137100000 end
os.startTimer=function(s) return py_next_timer(s) end
os.cancelTimer=function(_) end

function dofile(path)
  local code=py_read(path)
  local fn,err=load(code,"@"..tostring(path),"t",_G)
  if not fn then error(err) end
  return fn()
end
''')

    def _load_desktop(self):
        g = self.lua.globals()
        g.ctx = self.lua.table()
        g.ctx["process"] = self.lua.table_from({
            "cwd": "/home/caden",
            "pid": 100,
            "uid": 1000,
            "environment": self.lua.table(),
        })
        kernel = self.lua.table()
        kernel["version"] = self.lua.table_from({"version": "0.2.0", "kernel_abi": "cclua-1"})
        process = self.lua.table()
        process["all"] = self.lua.eval("function() return {{pid=1},{pid=2},{pid=100}} end")
        kernel["process"] = process
        kernel["device"] = self.lua.table_from({"devices": self.lua.table()})
        kernel["exec"] = self.lua.table_from({
            "resolve": self.lua.eval("function(_) return nil end"),
            "load": self.lua.eval("function(_) return nil,'not available in preview' end"),
        })
        g.ctx["kernel"] = kernel

        self.lua.execute(r'''
desktop_mod=dofile("/usr/lib/cclua/desktop/compositor.lua")
desktop_co=coroutine.create(function() return desktop_mod.run(ctx) end)
function desktop_start()
  return coroutine.resume(desktop_co)
end
function desktop_step(ev,a,b,c)
  return coroutine.resume(desktop_co,ev,a,b,c)
end
function desktop_status()
  return coroutine.status(desktop_co)
end
''')
        result = self.lua.globals().desktop_start()
        if not result or result[0] is not True:
            raise RuntimeError(f"desktop start failed: {result}")

    def step(self, event, a=None, b=None, c=None):
        result = self.lua.globals().desktop_step(event, a, b, c)
        if not result or result[0] is not True:
            raise RuntimeError(f"desktop event failed {event}: {result}")
        return result

    def capture(self, name, title):
        path = OUT / f"{name}.png"
        self.term.render_png(path, title)
        (OUT / f"{name}.txt").write_text(self.term.text_dump(), encoding="utf-8")
        return path

def make_contact_sheet(paths):
    images=[Image.open(p).convert("RGB") for p in paths]
    if not images:
        return None
    margin=20
    cols=2
    rows=(len(images)+cols-1)//cols
    w=max(i.width for i in images)
    h=max(i.height for i in images)
    sheet=Image.new("RGB",(cols*w+(cols+1)*margin,rows*h+(rows+1)*margin),(30,30,30))
    for i,img in enumerate(images):
        x=margin+(i%cols)*(w+margin)
        y=margin+(i//cols)*(h+margin)
        sheet.paste(img,(x,y))
    out=OUT/"desktop-contact-sheet.png"
    sheet.save(out)
    return out


def run_case(name,title,events):
    h=DesktopHarness()
    for event in events:
        h.step(*event)
    status=h.lua.globals().desktop_status()
    if status!="suspended":
        raise RuntimeError(f"{name}: desktop status {status}")
    dump=h.term.text_dump().splitlines()
    if len(dump)!=HEIGHT or any(len(line)!=WIDTH for line in dump):
        raise RuntimeError(f"{name}: invalid framebuffer geometry")
    return h.capture(name,title)


def main():
    cases=[
        ("00_workspace","Workspace",[]),
        ("01_terminal","Terminal",[
            ("mouse_click",1,2,4),
            *[("char",c) for c in "help"],
            ("key",257),
        ]),
        ("02_files","Files",[("mouse_click",1,2,7)]),
        ("03_settings","Settings",[("mouse_click",1,2,10)]),
        ("04_software_search","Software search",[
            ("mouse_click",1,2,13),
            *[("char",c) for c in "gnome"],
        ]),
        ("05_terminal_maximized","Maximized Terminal",[
            ("mouse_click",1,2,4),
            ("mouse_click",1,43,3),
        ]),
        ("06_multiwindow","Multi-window + Alt-Tab",[
            ("mouse_click",1,2,4),
            ("mouse_click",1,2,7),
            ("key",342),("key",258),("key_up",342),
        ]),
        ("07_dragged_window","Dragged Terminal",[
            ("mouse_click",1,2,4),
            ("mouse_click",1,15,3),
            ("mouse_drag",1,20,6),
            ("mouse_up",1,20,6),
        ]),
        ("08_resized_window","Resized Terminal",[
            ("mouse_click",1,2,4),
            ("mouse_click",1,49,17),
            ("mouse_drag",1,43,14),
            ("mouse_up",1,43,14),
        ]),
        ("09_close_window","Close Terminal",[
            ("mouse_click",1,2,4),
            ("mouse_click",1,48,3),
        ]),
    ]
    captures=[run_case(*case) for case in cases]
    sheet=make_contact_sheet(captures)
    print("SCENARIOS",len(captures))
    for item in captures: print("PNG",item)
    print("CONTACT_SHEET",sheet)
    print("ALL_SCENARIOS_OK")


if __name__=="__main__":
    main()
