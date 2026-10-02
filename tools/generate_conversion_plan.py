#!/usr/bin/env python3
import argparse,json
from pathlib import Path

def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--analysis",required=True)
    ap.add_argument("--registry",required=True)
    ap.add_argument("--output",required=True)
    args=ap.parse_args()

    analysis=Path(args.analysis)
    commands=load(analysis/"commands.json")
    units=load(analysis/"systemd-units.json")
    registry=load(args.registry)
    mapped={e["ubuntu"]:e for e in registry.get("entries",[])}

    work=[]
    for c in commands:
        name=Path(c["path"]).name
        reg=mapped.get(name)
        work.append({
            "kind":"command","name":name,"source":c["path"],
            "strategy":c["strategy"],
            "replacement":(reg or {}).get("replacement") or c.get("replacement"),
            "state":(reg or {}).get("state","unplanned"),
            "priority":1 if name in {"sh","bash","ls","cat","cp","mv","rm","mkdir","grep","find","uname","hostname","id","ps","kill"} else 3
        })
    for u in units:
        name=Path(u["path"]).name
        work.append({
            "kind":"service","name":name,"source":u["path"],
            "strategy":"service-reimplementation",
            "replacement":"service:"+name,
            "state":"unplanned",
            "priority":2
        })

    work.sort(key=lambda x:(x["priority"],x["kind"],x["name"]))
    out={"schema":1,"count":len(work),"items":work}
    p=Path(args.output);p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(json.dumps(out,indent=2),encoding="utf-8")
    print(f"Wrote {len(work)} conversion tasks to {p}")

if __name__=="__main__":
    main()
