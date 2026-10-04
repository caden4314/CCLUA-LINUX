#!/usr/bin/env python3
import argparse, base64, hashlib, json, os, subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def sha256(data):
    return hashlib.sha256(data).hexdigest()

def sha256_file(path):
    h=hashlib.sha256()
    with open(path,"rb") as f:
        while True:
            chunk=f.read(8*1024*1024)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()

def add_tree(records,src,prefix):
    src=Path(src)
    if not src.exists():
        return
    for path in sorted(p for p in src.rglob("*") if p.is_file()):
        rel=path.relative_to(src).as_posix()
        data=path.read_bytes()
        records.append({
            "path":f"{prefix}/{rel}",
            "size":len(data),
            "sha256":sha256(data),
            "encoding":"base64",
            "data":base64.b64encode(data).decode("ascii"),
        })

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--role",choices=["desktop","server"],required=True)
    ap.add_argument("--output")
    args=ap.parse_args()

    image_role=f"ubuntu-22.04-{args.role}"
    output=Path(args.output or ROOT/"dist"/f"{image_role}.luaiso")
    output.parent.mkdir(parents=True,exist_ok=True)

    records=[]
    add_tree(records,ROOT/"src"/"kernel","system/kernel")
    add_tree(records,ROOT/"src"/"init","system/init")
    add_tree(records,ROOT/"src"/"usr","system/usr")
    add_tree(records,ROOT/"src"/"lib","system/lib")
    add_tree(records,ROOT/"src"/"etc","system/etc")

    commit=subprocess.check_output(
        ["git","-C",str(ROOT),"rev-parse","HEAD"],text=True
    ).strip()
    payload_digest=hashlib.sha256()
    for rec in records:
        payload_digest.update(rec["path"].encode())
        payload_digest.update(b"\0")
        payload_digest.update(rec["sha256"].encode())
        payload_digest.update(b"\n")

    provenance={
        "ubuntu_release":"22.04.5",
        "source_iso":f"ubuntu-22.04.5-{args.role}-amd64.iso"
            if args.role=="desktop" else "ubuntu-22.04.5-live-server-amd64.iso",
    }
    iso=ROOT/".cache"/"ubuntu"/provenance["source_iso"]
    if iso.exists():
        provenance["source_iso_sha256"]=sha256_file(iso)

    generated=ROOT/"generated"/"ubuntu-22.04.5"/args.role
    inventory=generated/"filesystem-inventory.json"
    if inventory.exists():
        provenance["filesystem_inventory_sha256"]=sha256(inventory.read_bytes())

    manifest={
        "format":"cclua-luaiso",
        "format_version":1,
        "name":f"CCLUA Ubuntu 22.04.5 {args.role.title()}",
        "role":image_role,
        "version":"0.2.0",
        "channel":"development",
        "ubuntu_reference":"22.04.5",
        "architecture":"cclua",
        "build_id":commit[:12],
        "created_utc":datetime.now(timezone.utc).isoformat(),
        "entrypoint":"/system/init/init.lua",
        "required_runtime":1,
        "file_count":len(records),
        "payload_sha256":payload_digest.hexdigest(),
        "provenance":provenance,
    }
    payload={"manifest":manifest,"files":records}
    output.write_text(json.dumps(payload,separators=(",",":")),encoding="utf-8")
    print(json.dumps(manifest,indent=2))
    print("OUTPUT",output)
    print("BYTES",output.stat().st_size)

if __name__=="__main__":
    main()
