#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

def parse_manifest(path: Path):
    rows = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.rsplit(None, 1)
        if len(parts) == 2:
            name, version = parts
        else:
            name, version = parts[0], ""
        rows.append({"name": name, "version": version})
    return rows

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest", type=Path)
    ap.add_argument("--role", required=True, choices=["desktop", "server"])
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()

    packages = parse_manifest(args.manifest)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({
        "schema": 1,
        "distribution": "Ubuntu",
        "release": "22.04.5",
        "codename": "jammy",
        "role": args.role,
        "source_manifest": args.manifest.name,
        "package_count": len(packages),
        "packages": packages
    }, indent=2), encoding="utf-8")

    print(f"Wrote {len(packages)} packages to {args.output}")

if __name__ == "__main__":
    main()
