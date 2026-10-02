#!/usr/bin/env python3
import argparse
import hashlib
import json
import pathlib
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]

def download(url: str, dest: pathlib.Path):
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists():
        return
    print(f"GET {url}")
    with urllib.request.urlopen(url) as src, dest.open("wb") as out:
        while True:
            chunk = src.read(1024 * 1024)
            if not chunk:
                break
            out.write(chunk)

def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def parse_sums(path: pathlib.Path):
    result = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) >= 2:
            result[parts[-1].lstrip("*")] = parts[0].lower()
    return result

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--role", choices=["desktop", "server", "all"], default="all")
    ap.add_argument("--downloads", default=str(ROOT / ".cache" / "ubuntu"))
    ap.add_argument("--skip-iso", action="store_true",
                    help="Fetch manifests/checksums only; do not download multi-GB ISO files.")
    args = ap.parse_args()

    spec = json.loads((ROOT / "upstream" / "ubuntu-22.04.5.json").read_text())
    base = spec["base_url"]
    out = pathlib.Path(args.downloads)

    for name in (spec["checksum_file"], spec["signature_file"]):
        download(base + name, out / name)

    sums = parse_sums(out / spec["checksum_file"])
    roles = ["desktop", "server"] if args.role == "all" else [args.role]

    for role in roles:
        image = spec["images"][role]
        for key in ("manifest", "file_list"):
            name = image[key]
            download(base + name, out / name)

        if not args.skip_iso:
            name = image["iso"]
            path = out / name
            download(base + name, path)
            expected = sums.get(name)
            if not expected:
                raise SystemExit(f"No SHA256 entry found for {name}")
            actual = sha256(path)
            if actual != expected:
                raise SystemExit(
                    f"SHA256 mismatch for {name}\nexpected {expected}\nactual   {actual}"
                )
            print(f"OK SHA256 {name}")

if __name__ == "__main__":
    main()
