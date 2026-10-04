from pathlib import Path
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "src"

lua = LuaRuntime(unpack_returned_tuples=True)
compile_lua = lua.eval("""
function(source, name)
  local fn, err = load(source, name, "t", {})
  if fn then return true, nil end
  return false, tostring(err)
end
""")

files = sorted(SRC.rglob("*.lua"))
bad = []
for file in files:
    source = file.read_text(encoding="utf-8")
    ok, err = compile_lua(source, "@" + file.relative_to(ROOT).as_posix())
    if not ok:
        bad.append((file, err))

print("LUA_COMPILE_FILES", len(files))
print("LUA_COMPILE_BAD", len(bad))
for file, err in bad:
    print(file.relative_to(ROOT).as_posix(), err)

if bad:
    raise SystemExit(1)

print("LUA_COMPILE_OK")
