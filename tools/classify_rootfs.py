#!/usr/bin/env python3
"""Create the first-pass Ubuntu filesystem conversion inventory.

Input is an extracted Ubuntu root filesystem. This does not convert ELF files.
It classifies paths so later converters can build CCLUA-native replacements.
"""
import argparse
import hashlib
import json
import os
import pathlib
import stat

REUSE_PREFIXES = (
    "etc/",
    "usr/share/applications/",
    "usr/share/mime/",
)

REFERENCE_PREFIXES = (
    "usr/lib/systemd/",
    "lib/systemd/",
    "usr/share/man/",
)

def digest(path: pathlib.Path):
    if not path.is_file():
        return None
    h = hashlib.sha256()
    try:
        with path.open("rb") as f:
            for chunk in iter(lambda: f.read(1024 * 1024), b""):
                h.update(chunk)
        return h.hexdigest()
    except OSError:
        return None

def classify(rel: str, path: pathlib.Path):
    if rel.startswith(REUSE_PREFIXES):
        return "reusable-or-transform"
    if rel.startswith(REFERENCE_PREFIXES):
        return "behavior-reference"

    try:
        head = path.read_bytes()[:4] if path.is_file() else b""
    except OSError:
        head = b""

    if head == b"\x7fELF":
        return "cc-native-replacement"

    if rel.startswith(("bin/", "sbin/", "usr/bin/", "usr/sbin/")):
        return "behavior-reference"

    return "inventory"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rootfs", type=pathlib.Path)
    ap.add_argument("--image", required=True)
    ap.add_argument("--output", type=pathlib.Path, required=True)
    args = ap.parse_args()

    root = args.rootfs.resolve()
    rows = []

    for p in root.rglob("*"):
        rel = p.relative_to(root).as_posix()
        try:
            st = p.lstat()
        except OSError:
            continue

        if stat.S_ISDIR(st.st_mode):
            kind = "directory"
        elif stat.S_ISLNK(st.st_mode):
            kind = "symlink"
        elif stat.S_ISREG(st.st_mode):
            kind = "file"
        else:
            kind = "special"

        rows.append({
            "image": args.image,
            "path": "/" + rel,
            "kind": kind,
            "size": st.st_size,
            "classification": classify(rel, p),
            "sha256": digest(p),
            "replacement": None,
            "state": "unreviewed",
        })

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({
        "schema": 1,
        "image": args.image,
        "rootfs": str(root),
        "entries": rows,
    }, indent=2))
    print(f"Wrote {len(rows)} entries to {args.output}")

if __name__ == "__main__":
    main()
