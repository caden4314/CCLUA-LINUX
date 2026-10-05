import gzip
from pathlib import Path
import struct
import sys

def nbt_string(value: str) -> bytes:
    raw = value.encode("utf-8")
    return struct.pack(">H", len(raw)) + raw

def named_string(name: str, value: str) -> bytes:
    return b"\x08" + nbt_string(name) + nbt_string(value)

def named_byte(name: str, value: int) -> bytes:
    return b"\x01" + nbt_string(name) + struct.pack(">b", value)

def build(server_name: str, address: str) -> bytes:
    server = (
        named_string("name", server_name)
        + named_string("ip", address)
        + named_byte("hidden", 0)
        + b"\x00"
    )
    root = (
        b"\x0a"
        + nbt_string("")
        + b"\x09"
        + nbt_string("servers")
        + b"\x0a"
        + struct.pack(">i", 1)
        + server
        + b"\x00"
    )
    return gzip.compress(root)

if len(sys.argv) != 2:
    raise SystemExit("usage: write_servers_dat.py OUTPUT")

output = Path(sys.argv[1])
output.parent.mkdir(parents=True, exist_ok=True)
output.write_bytes(
    build(
        "CCLUA COMPUTERS2",
        "desktop-1r77lod.tail4ae277.ts.net:25565",
    )
)
print(output)
