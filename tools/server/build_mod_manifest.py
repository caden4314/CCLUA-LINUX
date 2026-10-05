import hashlib
import json
from pathlib import Path
import zipfile

INSTANCE = Path(r"E:\Minecraft\PrismLauncher\instances\CC Tweaked Creative\.minecraft")
MODS = INSTANCE / "mods"
OUT = Path(r"E:\Minecraft\CCLUA-LINUX\docs\minecraft-mod-manifest.json")

rows = []
for path in sorted(MODS.glob("*.jar")):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    row = {
        "file": path.name,
        "bytes": path.stat().st_size,
        "sha256": digest,
        "environment": "unknown",
        "id": None,
        "version": None,
        "depends": [],
    }
    try:
        with zipfile.ZipFile(path) as archive:
            if "fabric.mod.json" in archive.namelist():
                meta = json.loads(archive.read("fabric.mod.json"))
                row["environment"] = meta.get("environment", "*")
                row["id"] = meta.get("id")
                row["version"] = str(meta.get("version", ""))
                row["depends"] = sorted((meta.get("depends") or {}).keys())
    except Exception as exc:
        row["environment"] = f"error:{type(exc).__name__}"
        row["metadata_error"] = str(exc)
    rows.append(row)

OUT.write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8")
print(f"TOTAL={len(rows)}")
print("CLIENT_ONLY")
for row in rows:
    if row["environment"] == "client":
        print(f"{row['file']} | {row['id']} | {row['version']}")
print("SERVER_ONLY")
for row in rows:
    if row["environment"] == "server":
        print(f"{row['file']} | {row['id']} | {row['version']}")
print(
    "UNIVERSAL_OR_UNKNOWN="
    + str(sum(row["environment"] not in ("client", "server") for row in rows))
)
