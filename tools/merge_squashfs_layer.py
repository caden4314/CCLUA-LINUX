#!/usr/bin/env python3
import argparse
import json
import os
import shutil
from pathlib import Path

def parse_slt(path: Path):
    records=[]
    cur={}
    for raw in path.read_text(encoding="utf-8-sig",errors="replace").splitlines():
        line=raw.strip()
        if not line:
            if cur.get("Path") is not None:
                records.append(cur)
            cur={}
            continue
        if " = " in line:
            k,v=line.split(" = ",1)
            cur[k]=v
    if cur.get("Path") is not None:
        records.append(cur)
    return records

def remove_path(path: Path):
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path,ignore_errors=True)
    else:
        try:
            path.unlink()
        except FileNotFoundError:
            pass
        except IsADirectoryError:
            shutil.rmtree(path,ignore_errors=True)

def merge_tree(src: Path,dst: Path):
    copied_files=0
    copied_dirs=0
    for root,dirs,files in os.walk(src):
        rootp=Path(root)
        rel=rootp.relative_to(src)
        target=dst/rel
        target.mkdir(parents=True,exist_ok=True)
        copied_dirs+=1
        for name in files:
            s=rootp/name
            d=target/name
            d.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(s,d)
            copied_files+=1
    return copied_files,copied_dirs

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--base-root",type=Path,required=True)
    ap.add_argument("--overlay-root",type=Path,required=True)
    ap.add_argument("--catalog",type=Path,required=True)
    ap.add_argument("--output",type=Path,required=True)
    args=ap.parse_args()

    records=parse_slt(args.catalog)
    symlinks=[]
    whiteouts=[]
    special=[]

    for rec in records:
        p=rec.get("Path","").replace("\\","/")
        mode=rec.get("Mode","")
        size=rec.get("Size","")
        if not p:
            continue
        if mode.startswith("l"):
            symlinks.append({"path":"/"+p,"mode":mode,"size":size})
            remove_path(args.base_root/Path(p))
        elif mode=="c---------" and size in ("0",""):
            whiteouts.append({"path":"/"+p,"mode":mode})
            remove_path(args.base_root/Path(p))
        elif mode and mode[0] in "cbps":
            special.append({"path":"/"+p,"mode":mode,"size":size})

    copied_files,copied_dirs=merge_tree(args.overlay_root,args.base_root)

    result={
        "schema":1,
        "whiteouts":whiteouts,
        "symlinks":symlinks,
        "special":special,
        "copied_files":copied_files,
        "copied_directories":copied_dirs
    }
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2),encoding="utf-8")
    print(json.dumps({
        "whiteouts":len(whiteouts),
        "symlink_replacements":len(symlinks),
        "special":len(special),
        "copied_files":copied_files,
        "copied_directories":copied_dirs
    },indent=2))

if __name__=="__main__":
    main()
