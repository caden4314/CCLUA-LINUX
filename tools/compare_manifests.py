#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

def load(path):
    d=json.loads(Path(path).read_text(encoding="utf-8"))
    return {p["name"]:p["version"] for p in d["packages"]}

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("desktop")
    ap.add_argument("server")
    ap.add_argument("--output",required=True)
    args=ap.parse_args()

    desktop=load(args.desktop)
    server=load(args.server)

    common=sorted(set(desktop)&set(server))
    desktop_only=sorted(set(desktop)-set(server))
    server_only=sorted(set(server)-set(desktop))

    out={
        "schema":1,
        "release":"22.04.5",
        "counts":{
            "common":len(common),
            "desktop_only":len(desktop_only),
            "server_only":len(server_only)
        },
        "common":[{"name":n,"desktop_version":desktop[n],"server_version":server[n]} for n in common],
        "desktop_only":[{"name":n,"version":desktop[n]} for n in desktop_only],
        "server_only":[{"name":n,"version":server[n]} for n in server_only],
    }
    p=Path(args.output)
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(json.dumps(out,indent=2),encoding="utf-8")
    print(json.dumps(out["counts"],indent=2))

if __name__=="__main__":
    main()
