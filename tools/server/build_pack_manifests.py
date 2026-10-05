import hashlib
import json
from pathlib import Path

ROOT = Path(r"E:\Minecraft\CCLUA-LINUX")
SERVER_MODS = Path(r"E:\Minecraft\CCLUA-Server\mods")
CLIENT = json.loads((ROOT / "docs/minecraft-mod-manifest.json").read_text(encoding="utf-8"))
by_file = {row["file"]: row for row in CLIENT}

server_files = {p.name for p in SERVER_MODS.glob("*.jar")}
server = [by_file[name] for name in sorted(server_files) if name in by_file]
client_full = sorted(CLIENT, key=lambda row: row["file"].lower())

performance_ids = {
    "sodium", "sodium-extra", "reeses-sodium-options", "indium",
    "immediatelyfast", "entityculling", "ferritecore", "lithium",
}
visual_ids = {
    "iris", "continuity", "lambdynlights", "litematica", "malilib",
    "modmenu", "axiom", "emi", "jade", "worldedit",
}
performance = [row for row in client_full if row.get("id") in performance_ids]
visual = [row for row in client_full if row.get("id") in visual_ids]
layer_ids = performance_ids | visual_ids

common = [
    row for row in client_full
    if row["file"] in server_files and row.get("id") not in layer_ids
]

outputs = {
    "pack-common.json": common,
    "pack-server.json": server,
    "pack-client-full.json": client_full,
    "pack-client-performance.json": performance,
    "pack-client-visual.json": visual,
}

for name, rows in outputs.items():
    payload = {
        "schema": 1,
        "minecraft": "1.20.1",
        "fabric_loader": "0.19.5",
        "count": len(rows),
        "mods": rows,
    }
    (ROOT / "docs" / name).write_text(
        json.dumps(payload, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"{name}: {len(rows)}")

pack = Path(r"E:\Minecraft\CCLUA-ClientPack\20261005-144121\CCLUA-COMPUTERS2-Tailscale-v2.zip")
if pack.exists():
    digest = hashlib.sha256(pack.read_bytes()).hexdigest()
    (ROOT / "docs" / "minecraft-client-pack.json").write_text(
        json.dumps({
            "schema": 1,
            "file": pack.name,
            "bytes": pack.stat().st_size,
            "sha256": digest,
            "taildrop_name": "CCLUA-COMPUTERS2-Tailscale-1455.zip",
            "server": "desktop-1r77lod.tail4ae277.ts.net:25565",
            "fallback": "100.76.188.26:25565",
        }, indent=2) + "\n",
        encoding="utf-8",
    )
