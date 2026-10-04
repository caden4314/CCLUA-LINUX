from __future__ import annotations
import json
import os
import shutil
import tempfile
from pathlib import Path

from lupa import LuaRuntime

REPO=Path(r"E:\Minecraft\CCLUA-LINUX")
IMAGE=REPO/"dist"/"ubuntu-22.04-desktop.luaiso"
LOADER=REPO/"node"/"luaiso.lua"

root=Path(tempfile.mkdtemp(prefix="cclua-luaiso-test-"))
(root/"Boot").mkdir(parents=True)
shutil.copy2(IMAGE,root/"Boot"/"system.luaiso")

lua=LuaRuntime(unpack_returned_tuples=True,encoding="latin-1")

def resolve(path):
    return root/Path(str(path).replace("\\","/").lstrip("/").replace("/",os.sep))

def read_file(path):
    p=resolve(path)
    if not p.is_file():
        return None
    return p.read_bytes().decode("latin-1")

def write_file(path,data):
    p=resolve(path)
    p.parent.mkdir(parents=True,exist_ok=True)
    if isinstance(data,bytes):
        raw=data
    else:
        raw=str(data).encode("latin-1")
    p.write_bytes(raw)
    return True

def remove(path):
    p=resolve(path)
    if p.is_dir(): shutil.rmtree(p)
    elif p.exists(): p.unlink()

def mkdir(path):
    resolve(path).mkdir(parents=True,exist_ok=True)

def to_lua(obj):
    if isinstance(obj,dict):
        t=lua.table()
        for k,v in obj.items(): t[k]=to_lua(v)
        return t
    if isinstance(obj,list):
        t=lua.table()
        for i,v in enumerate(obj,1): t[i]=to_lua(v)
        return t
    return obj

g=lua.globals()
g.py_exists=lambda p: resolve(p).exists()
g.py_mkdir=mkdir
g.py_read=read_file
g.py_write=write_file
g.py_json=lambda raw: to_lua(json.loads(str(raw)))

lua.execute(r'''
fs={}
function fs.exists(p) return py_exists(p) end
function fs.makeDir(p) return py_mkdir(p) end
function fs.getDir(p)
  p=tostring(p or ""):gsub("\\","/"):gsub("/+$","")
  return p:match("^(.*)/[^/]+$") or ""
end
function fs.open(p,mode)
  mode=tostring(mode or "r")
  if mode:sub(1,1)=="r" then
    local raw=py_read(p)
    if raw==nil then return nil,"not found" end
    return {readAll=function() return raw end,close=function() end}
  end
  return {write=function(data) py_write(p,data) end,close=function() end}
end
textutils={}
function textutils.unserializeJSON(raw) return py_json(raw) end
''')

loader=lua.execute(LOADER.read_text(encoding="utf-8"))
result=loader.install("Boot/system.luaiso",lua.table_from({"clean":False}))
if result is None:
    raise RuntimeError("loader returned nil")

required=[
    "System/kernel/capabilities.lua",
    "System/kernel/scheduler.lua",
    "System/init/init.lua",
    "usr/bin/cclua-desktop.lua",
    "usr/lib/cclua/desktop/compositor.lua",
    "usr/lib/cclua/desktop/apps/terminal.lua",
]
missing=[p for p in required if not (root/Path(p)).is_file()]
print("ROLE",result["role"])
print("BUILD",result["build_id"])
print("FILES",result["file_count"])
print("MISSING",missing)
if missing:
    raise SystemExit(2)
print("TEST_ROOT",root)
print("LUAISO_LOADER_OK")
