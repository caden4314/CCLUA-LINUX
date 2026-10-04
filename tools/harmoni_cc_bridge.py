#!/usr/bin/env python3
"""Harmoni -> CCLUA audio bridge.

Watches Harmoni's music directory, detects files which are still being written,
waits for them to become stable, then converts completed audio to CC:Tweaked
DFPWM in a host-side cache.

The converted master library intentionally lives outside the Minecraft save:
CC:Tweaked computers in COMPUTERS2 currently have an 8 MiB filesystem quota.
"""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# Sibling import: shares the tested FFmpeg/probe helpers.
from music_import import ffmpeg_exe, probe, slugify

DEFAULT_SOURCE = Path(r"C:\Users\Jeff482\Downloads\Harmoni-Windows\music")
DEFAULT_CACHE = Path(__file__).resolve().parents[1] / ".cache" / "harmoni-bridge"

AUDIO_EXTENSIONS = {
    ".mp3", ".flac", ".ogg", ".oga", ".wav", ".m4a", ".aac", ".opus", ".wma"
}
TEMP_SUFFIXES = {
    ".part", ".partial", ".tmp", ".temp", ".download", ".crdownload"
}

STATE_WRITING = "WRITING"
STATE_STABLE = "STABLE"
STATE_READY = "READY"
STATE_CONVERTING = "CONVERTING"
STATE_DONE = "DONE"
STATE_ERROR = "ERROR"
STATE_MISSING = "MISSING"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def atomic_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    temp.replace(path)


def load_json(path: Path, default: Any) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return default


def source_key(path: Path) -> str:
    return str(path.resolve()).lower()


def output_stem(path: Path) -> str:
    short = hashlib.sha1(source_key(path).encode("utf-8")).hexdigest()[:10]
    return f"{slugify(path.stem)}-{short}"


def is_audio_candidate(path: Path) -> bool:
    if not path.is_file():
        return False
    lower = path.name.lower()
    if any(lower.endswith(suffix) for suffix in TEMP_SUFFIXES):
        return False
    return path.suffix.lower() in AUDIO_EXTENSIONS


def windows_exclusive_probe(path: Path) -> tuple[bool, str | None]:
    """Try to open a file while denying all sharing.

    If another process currently owns a write/read handle which is incompatible
    with exclusive access, CreateFileW fails. Combined with size/mtime stability
    this catches both actively-growing files and writers which pause briefly.
    """
    if os.name != "nt":
        try:
            with path.open("rb"):
                return True, None
        except OSError as exc:
            return False, str(exc)

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    CreateFileW = kernel32.CreateFileW
    CloseHandle = kernel32.CloseHandle

    CreateFileW.argtypes = [
        ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32,
        ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p
    ]
    CreateFileW.restype = ctypes.c_void_p
    CloseHandle.argtypes = [ctypes.c_void_p]
    CloseHandle.restype = ctypes.c_int

    GENERIC_READ = 0x80000000
    OPEN_EXISTING = 3
    FILE_ATTRIBUTE_NORMAL = 0x80
    INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value

    handle = CreateFileW(
        str(path),
        GENERIC_READ,
        0,  # no FILE_SHARE_* flags: require an exclusive snapshot
        None,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        None,
    )
    if handle == INVALID_HANDLE_VALUE:
        err = ctypes.get_last_error()
        return False, f"exclusive-open blocked (winerror {err})"
    try:
        return True, None
    finally:
        CloseHandle(handle)


def ffmpeg_validate(path: Path) -> tuple[bool, str | None]:
    """Quickly parse the source without transcoding it.

    This catches files whose container tail/header has not finished being
    written even when size/mtime happen to sit still for the stability window.
    """
    cmd = [
        ffmpeg_exe(), "-hide_banner", "-loglevel", "error",
        "-i", str(path), "-map", "0:a:0", "-f", "null", "-"
    ]
    proc = subprocess.run(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if proc.returncode == 0:
        return True, None
    msg = (proc.stderr or "").strip().splitlines()
    return False, (msg[-1] if msg else f"ffmpeg exited {proc.returncode}")


def convert_to_dfpwm(source: Path, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temp = output.with_suffix(output.suffix + ".part")
    if temp.exists():
        temp.unlink()

    cmd = [
        ffmpeg_exe(), "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(source),
        "-vn", "-map", "0:a:0",
        "-ac", "1", "-ar", "48000",
        "-f", "dfpwm", str(temp),
    ]
    try:
        subprocess.run(cmd, check=True)
        temp.replace(output)
    finally:
        if temp.exists():
            temp.unlink()


@dataclass
class BridgeConfig:
    source: Path
    cache: Path
    stable_seconds: float = 8.0
    poll_seconds: float = 1.0
    min_age_seconds: float = 2.0
    auto_convert: bool = True
    retry_seconds: float = 30.0
    http_enabled: bool = True
    http_bind: str = "127.0.0.1"
    http_port: int = 8765


class HarmoniBridge:
    def __init__(self, cfg: BridgeConfig):
        self.cfg = cfg
        self.state_path = cfg.cache / "state.json"
        self.status_path = cfg.cache / "status.json"
        self.catalog_path = cfg.cache / "catalog.json"
        self.library_dir = cfg.cache / "library"
        self.meta_dir = cfg.cache / "metadata"
        self.log_path = cfg.cache / "bridge.log"

        cfg.cache.mkdir(parents=True, exist_ok=True)
        self.library_dir.mkdir(parents=True, exist_ok=True)
        self.meta_dir.mkdir(parents=True, exist_ok=True)

        raw = load_json(self.state_path, {"schema": 1, "files": {}})
        self.records: dict[str, dict[str, Any]] = raw.get("files", {})
        self.running = True
        self.active_conversion: str | None = None
        self.last_catalog_write = 0.0
        self.httpd: ThreadingHTTPServer | None = None
        self.http_thread: threading.Thread | None = None

    def public_status(self) -> dict[str, Any]:
        status = load_json(self.status_path, {})
        return {
            "schema": 1,
            "updated_utc": status.get("updated_utc"),
            "active_conversion": bool(status.get("active_conversion")),
            "active_track": Path(status.get("active_conversion")).name if status.get("active_conversion") else None,
            "counts": status.get("counts", {}),
            "total": status.get("total", 0),
            "source_exists": status.get("source_exists", False),
            "catalog_count": load_json(self.catalog_path, {}).get("count", 0),
        }

    def public_catalog(self) -> dict[str, Any]:
        catalog = load_json(self.catalog_path, {"schema": 1, "tracks": [], "count": 0})
        base = f"http://127.0.0.1:{self.cfg.http_port}/v1"
        tracks = []
        for item in catalog.get("tracks", []):
            track_id = str(item.get("id") or "")
            if not track_id:
                continue
            tracks.append({
                "id": track_id,
                "title": item.get("title") or "Unknown",
                "artist": item.get("artist") or "",
                "album": item.get("album") or "",
                "duration": item.get("duration"),
                "bytes": item.get("dfpwm_bytes"),
                "sample_rate": 48000,
                "channels": 1,
                "format": "dfpwm",
                "source": "harmoni-bridge",
                "stream_url": f"{base}/tracks/{track_id}.dfpwm",
            })
        return {
            "schema": 1,
            "updated_utc": catalog.get("updated_utc"),
            "count": len(tracks),
            "tracks": tracks,
        }

    def track_path(self, track_id: str) -> Path | None:
        for rec in self.records.values():
            if rec.get("state") != STATE_DONE or str(rec.get("id")) != str(track_id):
                continue
            output = Path(str(rec.get("output") or ""))
            if output.is_file() and output.parent.resolve() == self.library_dir.resolve():
                return output
        return None

    def make_http_handler(self):
        bridge = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"
            server_version = "CCLUA-HarmoniBridge/0.3"

            def log_message(self, fmt: str, *args: Any) -> None:
                bridge.log("HTTP " + (fmt % args))

            def send_json(self, payload: dict[str, Any], status: int = 200) -> None:
                body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
                self.send_response(status)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(body)

            def send_track(self, track_id: str) -> None:
                path = bridge.track_path(track_id)
                if path is None:
                    self.send_json({"ok": False, "error": "track not found"}, HTTPStatus.NOT_FOUND)
                    return

                size = path.stat().st_size
                start, end = 0, size - 1
                partial = False
                header = self.headers.get("Range")
                if header and header.startswith("bytes="):
                    try:
                        value = header[6:].split(",", 1)[0]
                        left, right = value.split("-", 1)
                        if left:
                            start = max(0, min(size - 1, int(left)))
                        if right:
                            end = max(start, min(size - 1, int(right)))
                        partial = True
                    except (ValueError, IndexError):
                        self.send_response(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                        self.send_header("Content-Range", f"bytes */{size}")
                        self.send_header("Content-Length", "0")
                        self.end_headers()
                        return

                length = max(0, end - start + 1)
                self.send_response(HTTPStatus.PARTIAL_CONTENT if partial else HTTPStatus.OK)
                self.send_header("Content-Type", "audio/x-dfpwm")
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Content-Length", str(length))
                if partial:
                    self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
                self.send_header("Cache-Control", "public, max-age=3600")
                self.end_headers()

                if self.command == "HEAD":
                    return

                with path.open("rb") as handle:
                    handle.seek(start)
                    remaining = length
                    while remaining > 0:
                        chunk = handle.read(min(64 * 1024, remaining))
                        if not chunk:
                            break
                        try:
                            self.wfile.write(chunk)
                        except (BrokenPipeError, ConnectionResetError):
                            # Normal when a player stops/seeks and closes the
                            # HTTP stream before the source file is exhausted.
                            return
                        remaining -= len(chunk)

            def route(self) -> None:
                path = urlparse(self.path).path
                if path == "/v1/health":
                    self.send_json({"ok": True, "service": "harmoni-cc-bridge", **bridge.public_status()})
                elif path == "/v1/status":
                    self.send_json(bridge.public_status())
                elif path == "/v1/catalog":
                    self.send_json(bridge.public_catalog())
                elif path.startswith("/v1/tracks/") and path.endswith(".dfpwm"):
                    track_id = path[len("/v1/tracks/"):-len(".dfpwm")]
                    if not track_id or not all(c in "0123456789abcdefABCDEF" for c in track_id):
                        self.send_json({"ok": False, "error": "invalid track id"}, HTTPStatus.BAD_REQUEST)
                    else:
                        self.send_track(track_id)
                else:
                    self.send_json({"ok": False, "error": "not found"}, HTTPStatus.NOT_FOUND)

            def do_GET(self) -> None:
                self.route()

            def do_HEAD(self) -> None:
                self.route()

        return Handler

    def start_http(self) -> None:
        if not self.cfg.http_enabled or self.httpd is not None:
            return
        self.httpd = ThreadingHTTPServer(
            (self.cfg.http_bind, int(self.cfg.http_port)),
            self.make_http_handler(),
        )
        self.httpd.daemon_threads = True
        self.http_thread = threading.Thread(
            target=self.httpd.serve_forever,
            name="harmoni-cc-http",
            daemon=True,
        )
        self.http_thread.start()
        self.log(f"HTTP bridge listening on http://{self.cfg.http_bind}:{self.cfg.http_port}/v1")

    def stop_http(self) -> None:
        if self.httpd is None:
            return
        try:
            self.httpd.shutdown()
            self.httpd.server_close()
        finally:
            self.httpd = None
            self.http_thread = None

    def log(self, message: str) -> None:
        line = f"[{utc_now()}] {message}"
        print(line, flush=True)
        with self.log_path.open("a", encoding="utf-8") as handle:
            handle.write(line + "\n")

    def save_state(self) -> None:
        atomic_json(self.state_path, {
            "schema": 1,
            "updated_utc": utc_now(),
            "source": str(self.cfg.source),
            "cache": str(self.cfg.cache),
            "stable_seconds": self.cfg.stable_seconds,
            "files": self.records,
        })

    def write_status(self) -> None:
        counts: dict[str, int] = {}
        for rec in self.records.values():
            state = str(rec.get("state") or "UNKNOWN")
            counts[state] = counts.get(state, 0) + 1

        atomic_json(self.status_path, {
            "schema": 1,
            "updated_utc": utc_now(),
            "source": str(self.cfg.source),
            "cache": str(self.cfg.cache),
            "active_conversion": self.active_conversion,
            "counts": counts,
            "total": len(self.records),
            "source_exists": self.cfg.source.is_dir(),
        })

    def write_catalog(self) -> None:
        tracks = []
        for rec in self.records.values():
            if rec.get("state") != STATE_DONE:
                continue
            output = Path(str(rec.get("output") or ""))
            meta_path = Path(str(rec.get("metadata") or ""))
            if not output.is_file():
                continue
            meta = load_json(meta_path, {}) if meta_path.is_file() else {}
            tracks.append({
                "id": rec.get("id"),
                "title": meta.get("title") or Path(rec["source"]).stem,
                "artist": meta.get("artist") or "",
                "album": meta.get("album") or "",
                "duration": meta.get("duration"),
                "source_file": rec.get("source"),
                "dfpwm_file": str(output),
                "dfpwm_bytes": output.stat().st_size,
                "sample_rate": 48000,
                "channels": 1,
                "format": "dfpwm",
                "converted_utc": rec.get("converted_utc"),
            })
        tracks.sort(key=lambda x: ((x["artist"] or "").lower(), (x["title"] or "").lower()))
        atomic_json(self.catalog_path, {
            "schema": 1,
            "updated_utc": utc_now(),
            "tracks": tracks,
            "count": len(tracks),
        })

    def observe_file(self, path: Path, now: float) -> dict[str, Any]:
        key = source_key(path)
        rec = self.records.setdefault(key, {
            "id": hashlib.sha1(key.encode("utf-8")).hexdigest()[:16],
            "source": str(path),
            "first_seen_utc": utc_now(),
            "state": STATE_WRITING,
            "last_change_monotonic": now,
            "last_state_change_utc": utc_now(),
            "attempts": 0,
        })

        try:
            stat = path.stat()
        except OSError as exc:
            rec["state"] = STATE_MISSING
            rec["error"] = str(exc)
            return rec

        size = int(stat.st_size)
        mtime_ns = int(stat.st_mtime_ns)
        changed = rec.get("size") != size or rec.get("mtime_ns") != mtime_ns

        rec["size"] = size
        rec["mtime_ns"] = mtime_ns
        rec["mtime_utc"] = datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat()
        rec["last_seen_utc"] = utc_now()

        if changed:
            rec["last_change_monotonic"] = now
            self.set_state(rec, STATE_WRITING, "size/mtime changed")
            rec.pop("ready_reason", None)
            rec.pop("error", None)
            return rec

        last_change = float(rec.get("last_change_monotonic", now))
        if last_change > now:
            # The host rebooted since state.json was written. Monotonic clocks
            # reset across reboot, so restart the stability window safely.
            last_change = now
            rec["last_change_monotonic"] = now

        unchanged_for = now - last_change
        age = max(0.0, time.time() - stat.st_mtime)

        if (
            rec.get("converted_size") == size
            and rec.get("converted_mtime_ns") == mtime_ns
            and rec.get("output")
            and Path(str(rec["output"])).is_file()
        ):
            self.set_state(rec, STATE_DONE, "source unchanged since conversion")
            return rec

        if age < self.cfg.min_age_seconds or unchanged_for < self.cfg.stable_seconds:
            self.set_state(
                rec,
                STATE_STABLE if unchanged_for > 0 else STATE_WRITING,
                f"unchanged {unchanged_for:.1f}s; waiting for {self.cfg.stable_seconds:.1f}s",
            )
            return rec

        unlocked, lock_reason = windows_exclusive_probe(path)
        if not unlocked:
            rec["last_change_monotonic"] = now
            self.set_state(rec, STATE_WRITING, lock_reason or "source file is open")
            return rec

        self.set_state(rec, STATE_READY, f"stable {unchanged_for:.1f}s and exclusively readable")
        rec["ready_reason"] = "stable+exclusive"
        return rec

    def set_state(self, rec: dict[str, Any], state: str, reason: str | None = None) -> None:
        if rec.get("state") != state:
            rec["state"] = state
            rec["last_state_change_utc"] = utc_now()
            if reason:
                self.log(f"{state:10s} {Path(rec['source']).name}: {reason}")
        rec["state_reason"] = reason

    def output_paths(self, source: Path) -> tuple[Path, Path]:
        stem = output_stem(source)
        return self.library_dir / f"{stem}.dfpwm", self.meta_dir / f"{stem}.json"

    def convert_record(self, rec: dict[str, Any]) -> None:
        source = Path(rec["source"])
        output, meta_path = self.output_paths(source)

        # Skip a completed artifact if it matches the observed source identity.
        if (
            rec.get("state") == STATE_DONE
            and output.is_file()
            and rec.get("converted_size") == rec.get("size")
            and rec.get("converted_mtime_ns") == rec.get("mtime_ns")
        ):
            return

        self.active_conversion = str(source)
        self.set_state(rec, STATE_CONVERTING, "FFmpeg -> 48 kHz mono DFPWM")
        rec["attempts"] = int(rec.get("attempts") or 0) + 1
        self.write_status()
        self.save_state()

        try:
            valid, valid_reason = ffmpeg_validate(source)
            if not valid:
                rec["last_change_monotonic"] = time.monotonic()
                self.set_state(rec, STATE_WRITING, f"container not complete: {valid_reason}")
                rec["retry_after_monotonic"] = time.monotonic() + self.cfg.stable_seconds
                return

            metadata = probe(str(source))
            convert_to_dfpwm(source, output)

            # Validate the result before publishing it to the catalog.
            check = subprocess.run(
                [
                    ffmpeg_exe(), "-hide_banner", "-loglevel", "error",
                    "-f", "dfpwm", "-ar", "48000", "-i", str(output),
                    "-f", "null", "-"
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            if check.returncode != 0:
                raise RuntimeError((check.stderr or "DFPWM validation failed").strip())

            meta = {
                "schema": 1,
                "title": metadata.get("title") or source.stem,
                "artist": metadata.get("artist") or "",
                "album": metadata.get("album") or "",
                "duration": metadata.get("duration"),
                "source_file": str(source),
                "source_size": rec.get("size"),
                "source_mtime_ns": rec.get("mtime_ns"),
                "format": "dfpwm",
                "sample_rate": 48000,
                "channels": 1,
                "converted_utc": utc_now(),
                "dfpwm_file": str(output),
                "dfpwm_bytes": output.stat().st_size,
            }
            atomic_json(meta_path, meta)

            rec["output"] = str(output)
            rec["metadata"] = str(meta_path)
            rec["converted_size"] = rec.get("size")
            rec["converted_mtime_ns"] = rec.get("mtime_ns")
            rec["converted_utc"] = meta["converted_utc"]
            rec["output_bytes"] = output.stat().st_size
            rec.pop("error", None)
            self.set_state(rec, STATE_DONE, f"{output.stat().st_size} bytes CC-ready")
        except Exception as exc:
            rec["error"] = str(exc)
            rec["retry_after_monotonic"] = time.monotonic() + self.cfg.retry_seconds
            self.set_state(rec, STATE_ERROR, str(exc))
            if output.exists():
                output.unlink(missing_ok=True)
        finally:
            self.active_conversion = None
            self.save_state()
            self.write_catalog()
            self.write_status()

    def scan(self) -> list[dict[str, Any]]:
        now = time.monotonic()
        seen: set[str] = set()
        ready: list[dict[str, Any]] = []

        if not self.cfg.source.is_dir():
            self.write_status()
            return ready

        for path in sorted(self.cfg.source.iterdir()):
            if not is_audio_candidate(path):
                continue
            key = source_key(path)
            seen.add(key)
            rec = self.observe_file(path, now)
            if rec.get("state") == STATE_READY:
                ready.append(rec)
            elif rec.get("state") == STATE_ERROR:
                retry_after = float(rec.get("retry_after_monotonic") or 0)
                # A previously failed file is eligible again after the retry
                # delay, but only if it is still stable and unchanged.
                if now >= retry_after:
                    rec["last_change_monotonic"] = now - self.cfg.stable_seconds
                    rec["state"] = STATE_STABLE

        for key, rec in self.records.items():
            if key not in seen and Path(str(rec.get("source") or "")).parent == self.cfg.source:
                if rec.get("state") not in (STATE_DONE, STATE_MISSING):
                    self.set_state(rec, STATE_MISSING, "source disappeared")

        self.save_state()
        self.write_catalog()
        self.write_status()
        return ready

    def run_once(self, convert_limit: int = 1) -> None:
        ready = self.scan()
        if not self.cfg.auto_convert:
            return
        for rec in ready[:max(0, convert_limit)]:
            self.convert_record(rec)

    def run_forever(self) -> None:
        self.log(
            f"bridge start source={self.cfg.source} cache={self.cfg.cache} "
            f"stable={self.cfg.stable_seconds}s poll={self.cfg.poll_seconds}s"
        )
        self.start_http()
        try:
            while self.running:
                self.run_once(convert_limit=1)
                time.sleep(self.cfg.poll_seconds)
        finally:
            self.stop_http()
            self.log("bridge stopped")


def print_summary(cache: Path) -> None:
    status = load_json(cache / "status.json", {})
    print(json.dumps(status, indent=2))


def main() -> int:
    ap = argparse.ArgumentParser(description="Watch Harmoni music and prepare CC:Tweaked DFPWM")
    ap.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    ap.add_argument("--cache", type=Path, default=DEFAULT_CACHE)
    ap.add_argument("--stable-seconds", type=float, default=8.0)
    ap.add_argument("--poll-seconds", type=float, default=1.0)
    ap.add_argument("--min-age-seconds", type=float, default=2.0)
    ap.add_argument("--retry-seconds", type=float, default=30.0)
    ap.add_argument("--bind", default="127.0.0.1", help="HTTP bridge bind address")
    ap.add_argument("--port", type=int, default=8765, help="HTTP bridge port")
    ap.add_argument("--no-http", action="store_true", help="Disable the local streaming API")
    ap.add_argument("--once", action="store_true", help="Scan once and convert at most one READY file")
    ap.add_argument("--scan-only", action="store_true", help="Classify files but do not convert")
    ap.add_argument("--status", action="store_true", help="Print current bridge status and exit")
    args = ap.parse_args()

    if args.status:
        print_summary(args.cache)
        return 0

    cfg = BridgeConfig(
        source=args.source,
        cache=args.cache,
        stable_seconds=max(1.0, args.stable_seconds),
        poll_seconds=max(0.25, args.poll_seconds),
        min_age_seconds=max(0.0, args.min_age_seconds),
        auto_convert=not args.scan_only,
        retry_seconds=max(5.0, args.retry_seconds),
        http_enabled=not args.no_http,
        http_bind=str(args.bind),
        http_port=max(1, min(65535, int(args.port))),
    )
    bridge = HarmoniBridge(cfg)

    def stop_handler(signum, frame):
        bridge.running = False

    signal.signal(signal.SIGINT, stop_handler)
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, stop_handler)

    if args.once or args.scan_only:
        bridge.run_once(convert_limit=1)
        print_summary(cfg.cache)
        return 0

    bridge.run_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
