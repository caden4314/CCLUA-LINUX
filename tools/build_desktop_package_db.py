import json
from pathlib import Path

root = Path(r"E:\Minecraft\CCLUA-LINUX")
manifest = root / "upstream" / "ubuntu-22.04.5-desktop-amd64.manifest"
output = root / "src" / "usr" / "share" / "cclua" / "ubuntu-desktop-packages.json"

packages = []
for raw in manifest.read_text(encoding="utf-8").splitlines():
    if not raw.strip():
        continue
    parts = raw.split("\t", 1)
    packages.append({
        "name": parts[0],
        "version": parts[1] if len(parts) > 1 else "?"
    })

payload = {
    "schema": 1,
    "distribution": "Ubuntu",
    "release": "22.04.5",
    "role": "desktop",
    "package_count": len(packages),
    "packages": packages,
}
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
print(f"WROTE {len(packages)} packages -> {output}")
