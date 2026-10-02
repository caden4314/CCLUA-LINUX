#!/usr/bin/env python3
import argparse, json
from pathlib import Path

def parse_control(text):
    records=[]
    current={}
    key=None
    for raw in text.splitlines():
        if not raw.strip():
            if current:
                records.append(current); current={}; key=None
            continue
        if raw[0].isspace() and key:
            current[key]=current.get(key,"")+"\n"+raw[1:]
            continue
        if ":" in raw:
            key,val=raw.split(":",1)
            key=key.strip(); current[key]=val.strip()
    if current: records.append(current)
    return records

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("rootfs",type=Path)
    ap.add_argument("--output",type=Path,required=True)
    args=ap.parse_args()

    root=args.rootfs.resolve()
    status=root/"var/lib/dpkg/status"
    packages={}
    if status.exists():
        for rec in parse_control(status.read_text(encoding="utf-8",errors="replace")):
            name=rec.get("Package")
            if not name: continue
            packages[name]={
                "name":name,
                "version":rec.get("Version"),
                "architecture":rec.get("Architecture"),
                "status":rec.get("Status"),
                "priority":rec.get("Priority"),
                "section":rec.get("Section"),
                "essential":rec.get("Essential")=="yes",
                "depends":rec.get("Depends"),
                "pre_depends":rec.get("Pre-Depends"),
                "recommends":rec.get("Recommends"),
                "suggests":rec.get("Suggests"),
                "provides":rec.get("Provides"),
                "description":rec.get("Description"),
                "files":[]
            }

    info=root/"var/lib/dpkg/info"
    if info.exists():
        for listfile in info.glob("*.list"):
            stem=listfile.name[:-5]
            pkg=stem.split(":",1)[0]
            rec=packages.setdefault(pkg,{"name":pkg,"files":[]})
            try:
                files=[line.strip() for line in listfile.read_text(encoding="utf-8",errors="replace").splitlines() if line.strip()]
            except OSError:
                files=[]
            rec["files"]=files

    owners={}
    for name,rec in packages.items():
        for path in rec.get("files",[]):
            owners.setdefault(path,[]).append(name)

    out={
        "schema":1,
        "package_count":len(packages),
        "owned_path_count":len(owners),
        "packages":sorted(packages.values(),key=lambda x:x["name"]),
        "owners":owners
    }
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(out,indent=2),encoding="utf-8")
    print(f"packages={len(packages)} owned_paths={len(owners)}")

if __name__=="__main__":
    main()
