#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import pathlib
import re

COMMAND_DIRS = ("bin", "sbin", "usr/bin", "usr/sbin")
SYSTEMD_DIRS = ("etc/systemd", "lib/systemd", "usr/lib/systemd")
CONFIG_PREFIX = "etc/"
LIB_PREFIXES = ("lib/", "usr/lib/")
SCRIPT_EXT = {".sh", ".bash", ".py", ".pl", ".rb"}

def sha256(path: pathlib.Path):
    h = hashlib.sha256()
    try:
        with path.open("rb") as f:
            for chunk in iter(lambda: f.read(1024 * 1024), b""):
                h.update(chunk)
        return h.hexdigest()
    except OSError:
        return None

def head(path: pathlib.Path, n=4096):
    try:
        with path.open("rb") as f:
            return f.read(n)
    except OSError:
        return b""

def classify_file(rel: str, path: pathlib.Path):
    data = head(path)
    first = data.splitlines()[0] if data else b""

    if data.startswith(b"\x7fELF"):
        file_type = "elf"
    elif first.startswith(b"#!"):
        file_type = "script"
    elif path.suffix.lower() in SCRIPT_EXT:
        file_type = "script"
    else:
        file_type = "data"

    if rel.startswith(SYSTEMD_DIRS):
        category = "systemd"
        strategy = "behavior-reference"
    elif rel.startswith(COMMAND_DIRS):
        category = "command"
        strategy = "lua-replacement" if file_type == "elf" else "inspect-script"
    elif rel.startswith(CONFIG_PREFIX):
        category = "config"
        strategy = "reuse-or-transform"
    elif rel.startswith(LIB_PREFIXES):
        category = "library"
        strategy = "lua-library-or-compat"
    else:
        category = "data"
        strategy = "inventory"

    shebang = None
    if first.startswith(b"#!"):
        shebang = first.decode("utf-8", "replace")[2:].strip()

    return file_type, category, strategy, shebang

def replacement_for(rel: str, category: str):
    name = pathlib.PurePosixPath(rel).name
    if category == "command":
        return f"/usr/bin/{name}.lua"
    if category == "systemd":
        unit = name
        return f"service:{unit}"
    return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rootfs", type=pathlib.Path)
    ap.add_argument("--role", required=True, choices=["desktop", "server"])
    ap.add_argument("--output-dir", type=pathlib.Path, required=True)
    args = ap.parse_args()

    root = args.rootfs.resolve()
    out = args.output_dir
    out.mkdir(parents=True, exist_ok=True)

    inventory=[]
    commands=[]
    units=[]
    configs=[]
    libraries=[]

    for path in root.rglob("*"):
        try:
            if not path.is_file():
                continue
        except OSError:
            continue

        rel = path.relative_to(root).as_posix()
        file_type, category, strategy, shebang = classify_file(rel, path)
        rec = {
            "path": "/" + rel,
            "size": path.stat().st_size,
            "sha256": sha256(path),
            "file_type": file_type,
            "category": category,
            "strategy": strategy,
            "shebang": shebang,
            "replacement": replacement_for(rel, category),
            "state": "unreviewed"
        }
        inventory.append(rec)
        if category == "command": commands.append(rec)
        elif category == "systemd": units.append(rec)
        elif category == "config": configs.append(rec)
        elif category == "library": libraries.append(rec)

    summary = {
        "schema": 1,
        "release": "22.04.5",
        "role": args.role,
        "rootfs": str(root),
        "counts": {
            "files": len(inventory),
            "commands": len(commands),
            "systemd": len(units),
            "configs": len(configs),
            "libraries": len(libraries),
            "elf": sum(x["file_type"]=="elf" for x in inventory),
            "scripts": sum(x["file_type"]=="script" for x in inventory),
        }
    }

    datasets = {
        "inventory.json": inventory,
        "commands.json": commands,
        "systemd-units.json": units,
        "configs.json": configs,
        "libraries.json": libraries,
        "summary.json": summary,
    }
    for name,data in datasets.items():
        (out/name).write_text(json.dumps(data, indent=2), encoding="utf-8")

    print(json.dumps(summary, indent=2))

if __name__ == "__main__":
    main()
