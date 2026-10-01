from __future__ import annotations
import argparse
import shutil
from pathlib import Path

ROOT = Path(r"C:\Dev\CCLUA-LINUX")
DEFAULT_ID = 2710

def prepare(computer_id: int) -> Path:
    runtime = ROOT / "runtime" / "computer" / str(computer_id)
    runtime.mkdir(parents=True, exist_ok=True)
    boot_dir = runtime / ".cclua" / "boot"
    boot_dir.mkdir(parents=True, exist_ok=True)

    shutil.copy2(ROOT / "src" / "boot" / "bootstrap.lua", runtime / "startup.lua")
    shutil.copy2(
        ROOT / "dist" / "CCLUA-LINUX.luaiso",
        boot_dir / "CCLUA-LINUX.luaiso",
    )

    data = runtime / ".cclua" / "data"
    (data / "users" / "caden").mkdir(parents=True, exist_ok=True)
    (data / "apps").mkdir(parents=True, exist_ok=True)
    (data / "tmp").mkdir(parents=True, exist_ok=True)
    return runtime

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--id", type=int, default=DEFAULT_ID)
    args = ap.parse_args()
    print(prepare(args.id))

if __name__ == "__main__":
    main()
