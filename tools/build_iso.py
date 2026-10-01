from __future__ import annotations
import argparse
import base64
import binascii
import hashlib
import json
from pathlib import Path

MAGIC = "CCLUAISO/1"
DEFAULT_META = {
    "name": "CCLUA-LINUX",
    "version": "0.1.0",
    "arch": "cclua32",
    "abi": "cclua-1",
    "format": "1",
}

TEXT_SUFFIXES = {".lua", ".json", ".txt", ".md", ".cfg", ".ini", ".luapkg"}

def source_bytes(path: Path) -> bytes:
    data = path.read_bytes()
    if path.suffix.lower() in TEXT_SUFFIXES:
        text = data.decode("utf-8-sig")
        return text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
    return data

def b64(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")

def collect(src: Path) -> list[tuple[str, bytes]]:
    files = []
    for path in sorted(src.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(src).as_posix()
        files.append((rel, source_bytes(path)))
    return files
def build(src: Path, output: Path, meta: dict[str, str]) -> dict:
    files = collect(src)
    lines = [MAGIC]
    merged = dict(DEFAULT_META)
    merged.update({k: str(v) for k, v in meta.items()})
    merged["files"] = str(len(files))
    for key in sorted(merged):
        lines.append(f"META {key}={merged[key]}")
    manifest = []
    for rel, data in files:
        crc = f"{binascii.crc32(data) & 0xffffffff:08x}"
        lines.append(f"FILE {b64(rel.encode())} {crc} {b64(data)}")
        manifest.append({
            "path": rel,
            "bytes": len(data),
            "crc32": crc,
            "sha256": hashlib.sha256(data).hexdigest(),
        })
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="ascii")
    info = {
        "meta": merged,
        "files": manifest,
        "iso_bytes": output.stat().st_size,
        "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
    }
    output.with_suffix(output.suffix + ".json").write_text(
        json.dumps(info, indent=2), encoding="utf-8"
    )
    return info
def main() -> None:
    ap = argparse.ArgumentParser(description="Build a CCLUA-LINUX .luaiso image")
    ap.add_argument("--src", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--version", default=DEFAULT_META["version"])
    ap.add_argument("--channel", default="dev")
    args = ap.parse_args()
    info = build(args.src.resolve(), args.out.resolve(), {
        "version": args.version,
        "channel": args.channel,
    })
    print(f"built {args.out}")
    print(f"files={len(info['files'])}")
    print(f"bytes={info['iso_bytes']}")
    print(f"sha256={info['sha256']}")

if __name__ == "__main__":
    main()
