#!/usr/bin/env python3
import argparse
import hashlib
import json
import pathlib
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
CHUNK = 1024 * 1024
REPORT_EVERY = 64 * 1024 * 1024

def copy_response(resp, dest, mode, starting=0):
    written = starting
    next_report = ((written // REPORT_EVERY) + 1) * REPORT_EVERY
    with dest.open(mode) as out:
        while True:
            chunk = resp.read(CHUNK)
            if not chunk:
                break
            out.write(chunk)
            written += len(chunk)
            if written >= next_report:
                print(f"  {dest.name}: {written / (1024**3):.2f} GiB", flush=True)
                next_report += REPORT_EVERY
    return written

def download(url: str, dest: pathlib.Path, retries: int = 8):
    dest.parent.mkdir(parents=True, exist_ok=True)

    for attempt in range(1, retries + 1):
        existing = dest.stat().st_size if dest.exists() else 0
        headers = {"User-Agent": "CCLUA-LINUX-importer/1"}
        if existing:
            headers["Range"] = f"bytes={existing}-"

        req = urllib.request.Request(url, headers=headers)
        try:
            print(f"GET {url}" + (f" (resume at {existing})" if existing else ""), flush=True)
            with urllib.request.urlopen(req, timeout=60) as resp:
                code = getattr(resp, "status", resp.getcode())
                if existing and code == 206:
                    copy_response(resp, dest, "ab", existing)
                else:
                    if existing:
                        print("  server did not honor Range; restarting file", flush=True)
                    copy_response(resp, dest, "wb", 0)
            return
        except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as exc:
            if attempt >= retries:
                raise
            delay = min(30, 3 * attempt)
            print(f"  download error: {exc}; retry {attempt}/{retries} in {delay}s", flush=True)
            time.sleep(delay)

def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    total = path.stat().st_size
    done = 0
    next_report = REPORT_EVERY
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(CHUNK), b""):
            h.update(chunk)
            done += len(chunk)
            if done >= next_report:
                print(f"  verify {path.name}: {done/total:.0%}", flush=True)
                next_report += REPORT_EVERY
    return h.hexdigest()

def parse_sums(path: pathlib.Path):
    result = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) >= 2:
            result[parts[-1].lstrip("*")] = parts[0].lower()
    return result

def verify_iso(path: pathlib.Path, sums):
    expected = sums.get(path.name)
    if not expected:
        raise SystemExit(f"No SHA256 entry found for {path.name}")
    actual = sha256(path)
    if actual != expected:
        raise SystemExit(
            f"SHA256 mismatch for {path.name}\nexpected {expected}\nactual   {actual}"
        )
    print(f"OK SHA256 {path.name}", flush=True)

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
            path = out / image["iso"]
            download(base + image["iso"], path)
            verify_iso(path, sums)

if __name__ == "__main__":
    main()
