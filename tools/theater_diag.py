"""Remote theater diagnostics for CCLUA.

Designed for unattended validation through Caden Commander. It never needs
human listening to verify transport, media generation, runtime state, or logs.
"""
from __future__ import annotations
import argparse, hashlib, json, time, urllib.request
from pathlib import Path

SERVER = Path(r"E:\Minecraft\CCLUA-Server")
STATE = SERVER / r"world\computercraft\computer\23\var\lib\cclua\theater-state.json"
LOG = SERVER / r"logs\latest.log"
BRIDGE = "http://127.0.0.1:8766"

def get_json(url: str):
    with urllib.request.urlopen(url, timeout=10) as r:
        return json.loads(r.read())

def state():
    try:
        return json.loads(STATE.read_text(encoding="utf-8-sig"))
    except Exception as e:
        return {"_error": str(e)}

def report():
    health = get_json(BRIDGE + "/v1/health")
    s = state()
    av = (s.get("streams") or {}).get("av") or {}
    return {
        "bridge_ok": bool(health.get("ok")),
        "catalog_count": health.get("catalog_count"),
        "state": s.get("state"),
        "title": s.get("title"),
        "position": s.get("position"),
        "speakers_present": (s.get("hardware") or {}).get("speakers_present"),
        "speaker_submit_ok": av.get("speaker_submit_ok"),
        "speaker_submit_failed": av.get("speaker_submit_failed"),
        "speaker_submit_total": av.get("speaker_submit_total"),
        "audio_queue_depth": av.get("audio_queue_depth"),
        "audio_epoch": av.get("audio_epoch"),
        "audio_committed_epoch": av.get("audio_committed_epoch"),
        "stage": av.get("stage"),
    }

def media_probe(seconds=1.0):
    catalog = get_json(BRIDGE + "/v1/catalog").get("movies") or []
    if not catalog:
        return {"ok": False, "error": "empty catalog"}
    m = catalog[0]
    url = (f"{BRIDGE}/v1/movies/{m['id']}/av.segment"
           f"?start=0&seconds={seconds}&cols=64&rows=24&fps=20&color=stock16")
    t0 = time.perf_counter()
    with urllib.request.urlopen(url, timeout=30) as r:
        raw = r.read()
        ctype = r.headers.get("Content-Type")
    return {
        "ok": len(raw) > 0,
        "movie": m["title"],
        "bytes": len(raw),
        "sha256": hashlib.sha256(raw).hexdigest(),
        "content_type": ctype,
        "elapsed_ms": round((time.perf_counter()-t0)*1000, 1),
    }

def soak(seconds=30, interval=1.0):
    end=time.monotonic()+seconds
    rows=[]
    while time.monotonic()<end:
        r=report()
        r["time"]=time.time()
        rows.append(r)
        time.sleep(interval)
    failures=[r for r in rows if r.get("bridge_ok") is not True
              or r.get("speakers_present") not in (None,22)
              or (r.get("speaker_submit_failed") or 0)>0]
    return {"ok":not failures,"samples":len(rows),
            "failures":len(failures),"last":rows[-1] if rows else {}}

def main():
    ap=argparse.ArgumentParser()
    sub=ap.add_subparsers(dest="cmd",required=True)
    sub.add_parser("status")
    p=sub.add_parser("media-probe")
    p.add_argument("--seconds",type=float,default=1.0)
    p=sub.add_parser("soak")
    p.add_argument("--seconds",type=int,default=30)
    p.add_argument("--interval",type=float,default=1.0)
    args=ap.parse_args()
    if args.cmd=="status":
        out=report()
    elif args.cmd=="media-probe":
        out=media_probe(args.seconds)
    else:
        out=soak(args.seconds,args.interval)
    print(json.dumps(out,indent=2,sort_keys=True))
    if out.get("ok") is False:
        raise SystemExit(1)

if __name__=="__main__":
    main()
