#!/usr/bin/env python3
import argparse, base64, hashlib, json
from pathlib import Path

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("image")
    args=ap.parse_args()
    path=Path(args.image)
    image=json.loads(path.read_text(encoding="utf-8"))
    manifest=image.get("manifest") or {}
    if manifest.get("format")!="cclua-luaiso":
        raise SystemExit("invalid format")

    payload=hashlib.sha256()
    total=0
    bad=[]
    for rec in image.get("files") or []:
        try:
            data=base64.b64decode(rec["data"],validate=True)
        except Exception as exc:
            bad.append((rec.get("path"),f"base64: {exc}"))
            continue
        digest=hashlib.sha256(data).hexdigest()
        if len(data)!=int(rec.get("size",-1)):
            bad.append((rec.get("path"),"size"))
        if digest!=rec.get("sha256"):
            bad.append((rec.get("path"),"sha256"))
        total+=len(data)
        payload.update(str(rec["path"]).encode())
        payload.update(b"\0")
        payload.update(str(rec["sha256"]).encode())
        payload.update(b"\n")

    aggregate=payload.hexdigest()
    if aggregate!=manifest.get("payload_sha256"):
        bad.append(("<payload>","sha256"))

    print("IMAGE",path)
    print("ROLE",manifest.get("role"))
    print("BUILD",manifest.get("build_id"))
    print("FILES",len(image.get("files") or []))
    print("PAYLOAD_BYTES",total)
    print("CONTAINER_BYTES",path.stat().st_size)
    print("PAYLOAD_SHA256",aggregate)
    print("VALID",not bad)
    if bad:
        for item in bad[:20]: print("BAD",item)
        raise SystemExit(2)

if __name__=="__main__":
    main()
