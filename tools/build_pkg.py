from __future__ import annotations
import argparse, base64, hashlib, json
from pathlib import Path

MAGIC="CCLUAPKG/1"

def b64(data:bytes)->str:
    return base64.b64encode(data).decode("ascii")

def build(src:Path,out:Path)->dict:
    meta=json.loads((src/"package.json").read_text(encoding="utf-8"))
    lines=[MAGIC]
    commands=meta.get("commands",{})
    flat_commands=";".join(f"{k}:{v}" for k,v in sorted(commands.items()))
    scalar={
        "name":meta["name"],"version":meta["version"],
        "description":meta.get("description",""),
        "commands":flat_commands,
        "type":meta.get("type","application"),
        "architecture":meta.get("architecture","cclua32"),
    }
    for k,v in scalar.items():
        lines.append(f"META {k}={v}")
    files=[]
    payload=src/"payload"
    for path in sorted(payload.rglob("*")):
        if not path.is_file(): continue
        rel=path.relative_to(payload).as_posix()
        data=path.read_bytes()
        sha=hashlib.sha256(data).hexdigest()
        lines.append(f"FILE {b64(rel.encode())} {sha} {b64(data)}")
        files.append({"path":rel,"bytes":len(data),"sha256":sha})
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text("\n".join(lines)+"\n",encoding="ascii")
    return {"meta":meta,"files":files,"sha256":hashlib.sha256(out.read_bytes()).hexdigest()}

def main():
    ap=argparse.ArgumentParser(description="Build CCLUA-LINUX .luapkg package")
    ap.add_argument("source",type=Path)
    ap.add_argument("output",type=Path)
    args=ap.parse_args()
    info=build(args.source.resolve(),args.output.resolve())
    print(f"built {args.output}")
    print(f"files={len(info['files'])}")
    print(f"sha256={info['sha256']}")

if __name__=="__main__":
    main()
