from __future__ import annotations
import argparse, base64, hashlib, json, re
from pathlib import Path

MAGIC="CCLUAPKG/1"
TOKEN_RE=re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")

def safe_token(value:str,label:str)->str:
    value=str(value)
    if value in {".",".."} or not TOKEN_RE.fullmatch(value):
        raise ValueError(f"unsafe {label}: {value!r}")
    return value

def safe_rel(value:str)->str:
    value=str(value)
    p=Path(value)
    if not value or "\\" in value or p.is_absolute() or any(part in {"",".",".."} for part in p.parts):
        raise ValueError(f"unsafe package path: {value!r}")
    return p.as_posix()

TEXT_SUFFIXES={".lua",".json",".txt",".md",".cfg",".ini",".luapkg"}

def source_bytes(path:Path)->bytes:
    data=path.read_bytes()
    if path.suffix.lower() in TEXT_SUFFIXES:
        text=data.decode("utf-8-sig")
        return text.replace("\r\n","\n").replace("\r","\n").encode("utf-8")
    return data

def b64(data:bytes)->str:
    return base64.b64encode(data).decode("ascii")

def build(src:Path,out:Path)->dict:
    meta=json.loads((src/"package.json").read_text(encoding="utf-8"))
    lines=[MAGIC]
    name=safe_token(meta["name"],"package name")
    version=safe_token(meta["version"],"package version")
    commands=meta.get("commands",{})
    if not isinstance(commands,dict): raise ValueError("commands must be an object")
    clean_commands={safe_token(k,"command name"):safe_rel(v) for k,v in commands.items()}
    flat_commands=";".join(f"{k}:{v}" for k,v in sorted(clean_commands.items()))
    scalar={
        "name":name,"version":version,
        "description":meta.get("description",""),
        "commands":flat_commands,
        "type":meta.get("type","application"),
        "architecture":meta.get("architecture","cclua32"),
    }
    for k,v in scalar.items():
        value=str(v)
        if "\n" in value or "\r" in value: raise ValueError(f"metadata field {k} contains a newline")
        lines.append(f"META {k}={value}")
    files=[]
    payload=src/"payload"
    for path in sorted(payload.rglob("*")):
        if not path.is_file(): continue
        rel=safe_rel(path.relative_to(payload).as_posix())
        data=source_bytes(path)
        sha=hashlib.sha256(data).hexdigest()
        lines.append(f"FILE {b64(rel.encode())} {sha} {b64(data)}")
        files.append({"path":rel,"bytes":len(data),"sha256":sha})
    payload_names={f["path"] for f in files}
    missing=[p for p in clean_commands.values() if p not in payload_names]
    if missing: raise ValueError(f"command target missing from payload: {missing[0]}")
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
