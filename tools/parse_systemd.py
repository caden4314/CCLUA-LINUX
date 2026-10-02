#!/usr/bin/env python3
import argparse, configparser, json
from pathlib import Path

UNIT_DIRS=("etc/systemd/system","lib/systemd/system","usr/lib/systemd/system")

def parse_unit(path: Path):
    cp=configparser.ConfigParser(interpolation=None, strict=False, delimiters=("="))
    cp.optionxform=str
    try:
        cp.read(path,encoding="utf-8")
    except Exception:
        return None
    def get(section,key):
        try:return cp.get(section,key,fallback=None)
        except Exception:return None
    return {
        "name":path.name,
        "description":get("Unit","Description"),
        "requires":get("Unit","Requires"),
        "wants":get("Unit","Wants"),
        "after":get("Unit","After"),
        "before":get("Unit","Before"),
        "type":get("Service","Type"),
        "exec_start":get("Service","ExecStart"),
        "exec_stop":get("Service","ExecStop"),
        "restart":get("Service","Restart"),
        "wanted_by":get("Install","WantedBy"),
    }

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("rootfs",type=Path)
    ap.add_argument("--output",type=Path,required=True)
    args=ap.parse_args()
    root=args.rootfs.resolve()
    units=[]
    seen=set()
    for rel in UNIT_DIRS:
        d=root/rel
        if not d.exists(): continue
        for p in sorted(d.rglob("*")):
            if not p.is_file() or p.suffix not in {".service",".socket",".target",".timer",".mount",".path"}:
                continue
            key=p.name
            rec=parse_unit(p)
            if not rec: continue
            rec["source_path"]="/"+p.relative_to(root).as_posix()
            rec["kind"]=p.suffix.lstrip(".")
            rec["shadowed"]=key in seen
            seen.add(key)
            units.append(rec)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps({"schema":1,"count":len(units),"units":units},indent=2),encoding="utf-8")
    print(f"Wrote {len(units)} units to {args.output}")

if __name__=="__main__":
    main()
