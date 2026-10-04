#!/usr/bin/env python3
import argparse
import json
import os
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

REPO = Path(r"E:\Minecraft\CCLUA-LINUX")
WORLD = Path(r"E:\Minecraft\PrismLauncher\instances\CC Tweaked Creative\.minecraft\saves\COMPUTERS2")
TARGET = WORLD / "computercraft" / "computer" / "22"
PROFILE = REPO / "node" / "test-client.machine.json"
IMAGE = REPO / "dist" / "ubuntu-22.04-desktop.luaiso"
LOADER = REPO / "node" / "luaiso.lua"

def copy_tree(src: Path, dst: Path):
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)

def copy_defaults(src: Path, dst: Path):
    dst.mkdir(parents=True, exist_ok=True)
    for item in src.iterdir():
        out = dst / item.name
        if item.is_dir():
            copy_defaults(item, out)
        elif not out.exists():
            shutil.copy2(item, out)

def git_head():
    return subprocess.check_output(
        ["git", "-C", str(REPO), "rev-parse", "HEAD"],
        text=True
    ).strip()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    if not TARGET.exists():
        raise SystemExit(
            "REFUSING: Computer 22 filesystem does not exist yet. "
            "Turn TEST_CLIENT on once so CC:Tweaked creates it, then rerun."
        )

    existing_machine = TARGET / "etc" / "cclua" / "machine.json"
    if existing_machine.exists() and not args.force:
        try:
            existing = json.loads(existing_machine.read_text(encoding="utf-8"))
        except Exception:
            existing = {}
        if existing.get("role") or existing.get("hostname"):
            raise SystemExit(
                "REFUSING: target already has a machine profile. "
                "Use --force only after verifying it is TEST_CLIENT."
            )

    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = TARGET.parent / f"22-backup-pre-desktop-{ts}"
    shutil.copytree(TARGET, backup)

    for rel in [
        "System", "Boot", "home/caden", "root", "srv", "tmp",
        "var/lib/cclua", "var/log/cclua", "etc/cclua",
    ]:
        (TARGET / rel).mkdir(parents=True, exist_ok=True)

    shutil.copy2(REPO / "node" / "startup.lua", TARGET / "startup.lua")
    shutil.copy2(LOADER, TARGET / "luaiso.lua")
    shutil.copy2(PROFILE, TARGET / "etc" / "cclua" / "machine.json")

    if IMAGE.exists():
        shutil.copy2(IMAGE, TARGET / "Boot" / "system.luaiso")
        (TARGET / "Boot" / "install-pending").write_text(
            "ubuntu-22.04-desktop\n", encoding="utf-8", newline="\n"
        )
    else:
        # Development fallback while the immutable image is being assembled.
        copy_tree(REPO / "src" / "kernel", TARGET / "System" / "kernel")
        copy_tree(REPO / "src" / "init", TARGET / "System" / "init")
        copy_tree(REPO / "src" / "usr", TARGET / "usr")
        copy_tree(REPO / "src" / "lib", TARGET / "lib")
        copy_defaults(REPO / "src" / "etc", TARGET / "etc")

    head = git_head()
    (TARGET / "var" / "lib" / "cclua" / "installed-commit").write_text(
        head + "\n", encoding="utf-8", newline="\n"
    )

    boot = {
        "schema": 2,
        "state": "PROVISIONED",
        "slot": "A",
        "commit": head,
        "profile": "ubuntu-22.04-desktop",
    }
    (TARGET / "var" / "lib" / "cclua" / "boot.json").write_text(
        json.dumps(boot, separators=(",", ":")) + "\n",
        encoding="utf-8", newline="\n"
    )

    print("PROVISIONED", TARGET)
    print("BACKUP", backup)
    print("COMMIT", head)
    print("PROFILE", PROFILE)

if __name__ == "__main__":
    main()
