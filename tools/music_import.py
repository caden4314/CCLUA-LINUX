#!/usr/bin/env python3
"""Import an authorized/local audio file into a CCLUA Desktop music library.

This intentionally defaults to local files. HTTP(S) sources require --allow-url
so a caller must explicitly acknowledge they are importing a source they may
download.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

try:
    import imageio_ffmpeg
except ImportError:
    imageio_ffmpeg = None

DEFAULT_WORLD = Path(r"E:\Minecraft\PrismLauncher\instances\CC Tweaked Creative\.minecraft\saves\COMPUTERS2")

def ffmpeg_exe() -> str:
    if imageio_ffmpeg is not None:
        return imageio_ffmpeg.get_ffmpeg_exe()
    found = shutil.which("ffmpeg")
    if found:
        return found
    raise RuntimeError("FFmpeg 5.1+ is required (system ffmpeg or imageio-ffmpeg)")

def slugify(value: str) -> str:
    value = re.sub(r"[^A-Za-z0-9._ -]+", "_", value).strip(" ._-")
    value = re.sub(r"\s+", " ", value)
    return value[:96] or "track"

def is_url(value: str) -> bool:
    return value.startswith("http://") or value.startswith("https://")

def spotify_oembed(url: str) -> dict:
    endpoint = "https://open.spotify.com/oembed?url=" + urllib.parse.quote(url, safe="")
    req = urllib.request.Request(endpoint, headers={"User-Agent": "CCLUA-Music-Importer/0.2"})
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return json.loads(response.read().decode("utf-8"))
    except Exception as first_error:
        # Some Windows Python installs do not inherit the Windows root store.
        # Prefer a verified curl fallback rather than disabling TLS checks.
        curl = shutil.which("curl")
        if curl:
            proc = subprocess.run(
                [curl, "-fsSL", "-A", "CCLUA-Music-Importer/0.2", endpoint],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            if proc.returncode == 0:
                return json.loads(proc.stdout)
        raise RuntimeError(f"Spotify metadata lookup failed: {first_error}") from first_error

def probe(source: str) -> dict:
    proc = subprocess.run(
        [ffmpeg_exe(), "-hide_banner", "-i", source, "-f", "null", "-"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    text = proc.stderr or ""
    meta = {}
    dur = re.search(r"Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)", text)
    if dur:
        meta["duration"] = int(dur.group(1)) * 3600 + int(dur.group(2)) * 60 + float(dur.group(3))
    for key in ("title", "artist", "album"):
        m = re.search(rf"^\s*{key}\s*:\s*(.+?)\s*$", text, flags=re.IGNORECASE | re.MULTILINE)
        if m:
            meta[key] = m.group(1).strip()
    return meta

def convert(source: str, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temp = output.with_suffix(output.suffix + ".part")
    if temp.exists():
        temp.unlink()
    cmd = [
        ffmpeg_exe(), "-hide_banner", "-loglevel", "error", "-y",
        "-i", source,
        "-vn", "-ac", "1", "-ar", "48000",
        "-f", "dfpwm", str(temp),
    ]
    try:
        subprocess.run(cmd, check=True)
        temp.replace(output)
    finally:
        if temp.exists():
            temp.unlink()

def main() -> int:
    ap = argparse.ArgumentParser(description="Import audio into CCLUA Music")
    ap.add_argument("source", help="Local MP3/FLAC/OGG/WAV/etc. path, or URL with --allow-url")
    ap.add_argument("--world", type=Path, default=DEFAULT_WORLD)
    ap.add_argument("--computer", type=int, default=22)
    ap.add_argument("--title")
    ap.add_argument("--artist")
    ap.add_argument("--album")
    ap.add_argument("--spotify-url")
    ap.add_argument("--allow-url", action="store_true",
                    help="Allow an HTTP(S) source you are authorized to download")
    ap.add_argument("--replace", action="store_true")
    args = ap.parse_args()

    source = args.source
    if is_url(source) and not args.allow_url:
        print("Refusing URL source without --allow-url.", file=sys.stderr)
        print("Use --allow-url only for audio you are authorized to download.", file=sys.stderr)
        return 2
    if not is_url(source):
        src = Path(source).expanduser().resolve()
        if not src.is_file():
            print(f"Source file not found: {src}", file=sys.stderr)
            return 2
        source = str(src)

    metadata = probe(source)

    spotify = None
    if args.spotify_url:
        try:
            spotify = spotify_oembed(args.spotify_url)
        except Exception as exc:
            print(f"Warning: Spotify metadata lookup failed: {exc}", file=sys.stderr)

    title = args.title or (spotify or {}).get("title") or metadata.get("title")
    if not title:
        title = Path(urllib.parse.urlparse(source).path).stem if is_url(source) else Path(source).stem
    artist = args.artist or metadata.get("artist") or ""
    album = args.album or metadata.get("album") or ""

    base = slugify(f"{artist} - {title}" if artist else title)
    library = args.world / "computercraft" / "computer" / str(args.computer) / "home" / "caden" / "Music"
    library.mkdir(parents=True, exist_ok=True)
    output = library / f"{base}.dfpwm"
    sidecar = library / f"{base}.json"

    if output.exists() and not args.replace:
        print(f"Track already exists: {output}", file=sys.stderr)
        print("Use --replace to overwrite it.", file=sys.stderr)
        return 3

    print(f"Converting: {source}")
    print(f"Target:     {output}")
    convert(source, output)

    info = {
        "schema": 1,
        "title": title,
        "artist": artist,
        "album": album,
        "duration": metadata.get("duration"),
        "source": "url" if is_url(source) else "local-file",
        "source_name": Path(urllib.parse.urlparse(source).path).name if is_url(source) else Path(source).name,
        "spotify_url": args.spotify_url,
        "spotify_thumbnail_url": (spotify or {}).get("thumbnail_url"),
        "imported_utc": datetime.now(timezone.utc).isoformat(),
        "format": "dfpwm",
        "sample_rate": 48000,
        "channels": 1,
    }
    sidecar.write_text(json.dumps(info, indent=2), encoding="utf-8")

    print(f"Imported:   {title}")
    if artist:
        print(f"Artist:     {artist}")
    if info["duration"] is not None:
        print(f"Duration:   {info['duration']:.1f}s")
    print(f"Bytes:      {output.stat().st_size}")
    print(f"Metadata:   {sidecar}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
