"""CCLUA Theater host bridge.

Serves local movie metadata plus synchronized-friendly 48 kHz mono PCM and
ComputerCraft blit-frame video. Expensive FFmpeg scaling/color reduction is
kept on Windows so the Minecraft computer only feeds speaker buffers and
blits terminal rows.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import numpy as np

from music_import import NO_WINDOW, ffmpeg_exe

DEFAULT_LIBRARY = Path(r"E:\Minecraft\Theater\Movies")
DEFAULT_BIND = "127.0.0.1"
DEFAULT_PORT = 8766
MOVIE_EXTENSIONS = {".mp4", ".mkv", ".webm", ".mov", ".m4v", ".avi"}

# Standard CC:Tweaked 16-colour palette, indexed by blit nibble 0..f.
PALETTE = np.array([
    (240,240,240),(242,178,51),(229,127,216),(153,178,242),
    (222,222,108),(127,204,25),(242,178,204),(76,76,76),
    (153,153,153),(76,153,178),(178,102,229),(51,102,204),
    (127,102,76),(87,166,78),(204,76,76),(17,17,17),
], dtype=np.int32)
HEX = b"0123456789abcdef"

def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()

def movie_id(path: Path) -> str:
    return hashlib.sha1(path.name.lower().encode("utf-8")).hexdigest()[:16]

def parse_duration(stderr: str) -> float | None:
    m = re.search(r"Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)", stderr or "")
    if not m:
        return None
    return int(m.group(1))*3600 + int(m.group(2))*60 + float(m.group(3))

def probe_movie(path: Path) -> dict:
    # Reading container/stream headers is enough for metadata. Do not decode the
    # entire feature here: catalog scans must stay fast even for multi-gigabyte movies.
    proc = subprocess.run(
        [ffmpeg_exe(), "-hide_banner", "-i", str(path)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        creationflags=NO_WINDOW,
    )
    text = proc.stderr or ""
    width = height = None
    vm = re.search(r"Video:.*?\b(\d{2,5})x(\d{2,5})\b", text)
    if vm:
        width, height = int(vm.group(1)), int(vm.group(2))
    return {
        "duration": parse_duration(text),
        "source_width": width,
        "source_height": height,
    }

def scan_library(root: Path, probe_cache: dict[str, tuple[int,int,dict]] | None = None) -> list[dict]:
    root.mkdir(parents=True, exist_ok=True)
    cache = probe_cache if probe_cache is not None else {}
    out = []
    seen: set[str] = set()
    for path in sorted(root.iterdir(), key=lambda p: p.name.lower()):
        if not path.is_file() or path.suffix.lower() not in MOVIE_EXTENSIONS:
            continue
        stat = path.stat()
        key = str(path.resolve()).lower()
        seen.add(key)
        signature = (int(stat.st_size), int(stat.st_mtime_ns))
        cached = cache.get(key)
        if cached and cached[0] == signature[0] and cached[1] == signature[1]:
            meta = dict(cached[2])
        else:
            meta = probe_movie(path)
            cache[key] = (signature[0], signature[1], dict(meta))
        mid = movie_id(path)
        out.append({
            "id": mid,
            "title": path.stem,
            "file": path.name,
            "bytes": stat.st_size,
            "modified_utc": datetime.fromtimestamp(stat.st_mtime, timezone.utc).isoformat(),
            **meta,
            "audio_url": f"/v1/movies/{mid}/audio.pcm",
            "video_url": f"/v1/movies/{mid}/video.blit",
        })
    for key in list(cache):
        if key not in seen:
            cache.pop(key, None)
    return out

def choose_two(values: list[int]) -> tuple[int,int]:
    counts = {}
    first = {}
    for i, v in enumerate(values):
        counts[v] = counts.get(v, 0) + 1
        first.setdefault(v, i)
    ordered = sorted(counts, key=lambda v: (-counts[v], first[v]))
    a = ordered[0]
    b = ordered[1] if len(ordered) > 1 else a
    return a, b

def encode_texel(values: list[int]) -> tuple[int,int,int]:
    a, b = choose_two(values)
    if a == b:
        return 32, a, a

    bits = []
    pa, pb = PALETTE[a], PALETTE[b]
    for v in values:
        if v == a:
            bits.append(1)
        elif v == b:
            bits.append(0)
        else:
            pv = PALETTE[v]
            da = int(np.sum((pv-pa)*(pv-pa)))
            db = int(np.sum((pv-pb)*(pv-pb)))
            bits.append(1 if da <= db else 0)

    s6 = bits[5]
    char = 128
    for i in range(5):
        if bits[i] != s6:
            char += 1 << i
    if s6 == 0:
        fg, bg = a, b
    else:
        fg, bg = b, a
    return char, fg, bg
def encode_frame(rgb: bytes, cols: int, rows: int) -> bytes:
    width, height = cols*2, rows*3
    arr = np.frombuffer(rgb, dtype=np.uint8)
    if arr.size != width*height*3:
        raise ValueError(f"bad raw frame size {arr.size}, expected {width*height*3}")
    arr = arr.reshape(height, width, 3).astype(np.int32)

    # Nearest fixed CC palette colour for each physical subpixel.
    diff = arr[:, :, None, :] - PALETTE[None, None, :, :]
    idx = np.argmin(np.sum(diff*diff, axis=3), axis=2).astype(np.uint8)

    frame = bytearray()
    for cy in range(rows):
        chars = bytearray(cols)
        fgs = bytearray(cols)
        bgs = bytearray(cols)
        py = cy*3
        for cx in range(cols):
            px = cx*2
            vals = [
                int(idx[py,px]), int(idx[py,px+1]),
                int(idx[py+1,px]), int(idx[py+1,px+1]),
                int(idx[py+2,px]), int(idx[py+2,px+1]),
            ]
            ch, fg, bg = encode_texel(vals)
            chars[cx] = ch
            fgs[cx] = HEX[fg]
            bgs[cx] = HEX[bg]
        frame.extend(chars)
        frame.extend(fgs)
        frame.extend(bgs)
    return bytes(frame)

@dataclass
class BridgeConfig:
    library: Path
    bind: str = DEFAULT_BIND
    port: int = DEFAULT_PORT

class TheaterBridge:
    def __init__(self, cfg: BridgeConfig):
        self.cfg = cfg
        self.started = utc_now()
        self._lock = threading.RLock()
        self._catalog: list[dict] = []
        self._catalog_at = 0.0
        self._probe_cache: dict[str, tuple[int,int,dict]] = {}

    def catalog(self, max_age: float = 3.0) -> list[dict]:
        with self._lock:
            now = time.monotonic()
            if now-self._catalog_at >= max_age:
                self._catalog = scan_library(self.cfg.library,self._probe_cache)
                self._catalog_at = now
            return [dict(x) for x in self._catalog]

    def lookup(self, mid: str) -> tuple[dict, Path] | tuple[None,None]:
        for item in self.catalog(max_age=3.0):
            if item["id"] == mid:
                path = self.cfg.library/item["file"]
                if path.is_file():
                    return item, path
        return None, None

class Handler(BaseHTTPRequestHandler):
    server_version = "CCLUATheater/0.1"
    protocol_version = "HTTP/1.0"

    @property
    def bridge(self) -> TheaterBridge:
        return self.server.bridge  # type: ignore[attr-defined]

    def log_message(self, fmt, *args):
        return

    def json(self, payload: dict, code=200):
        raw = json.dumps(payload, separators=(",",":")).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type","application/json")
        self.send_header("Content-Length",str(len(raw)))
        self.send_header("Cache-Control","no-store")
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        q = parse_qs(parsed.query)

        if path == "/v1/health":
            movies = self.bridge.catalog()
            self.json({
                "ok": True,
                "service": "cclua-theater-bridge",
                "schema": 1,
                "started_utc": self.bridge.started,
                "library": str(self.bridge.cfg.library),
                "catalog_count": len(movies),
                "video": {"format":"cc-blit-2x3","default_cols":144,"default_rows":54,"default_fps":12},
                "audio": {"format":"pcm_s8","sample_rate":48000,"channels":1},
            })
            return

        if path == "/v1/catalog":
            self.json({"schema":1,"updated_utc":utc_now(),"movies":self.bridge.catalog()})
            return

        m = re.fullmatch(r"/v1/movies/([0-9a-f]{16})/(audio\.pcm|video\.blit)", path)
        if not m:
            self.json({"ok":False,"error":"not found"},404)
            return
        mid, kind = m.group(1), m.group(2)
        meta, source = self.bridge.lookup(mid)
        if not meta or not source:
            self.json({"ok":False,"error":"movie not found"},404)
            return

        try:
            start = max(0.0, float((q.get("start") or ["0"])[0]))
        except Exception:
            start = 0.0

        if kind == "audio.pcm":
            self.stream_audio(source, start)
        else:
            try:
                cols = max(16,min(160,int((q.get("cols") or ["144"])[0])))
                rows = max(9,min(60,int((q.get("rows") or ["54"])[0])))
                fps = max(2,min(20,float((q.get("fps") or ["12"])[0])))
            except Exception:
                self.json({"ok":False,"error":"invalid video geometry"},400)
                return
            self.stream_video(source,start,cols,rows,fps)

    def stream_audio(self, source: Path, start: float):
        cmd = [ffmpeg_exe(),"-hide_banner","-loglevel","error"]
        if start > 0:
            cmd += ["-ss",f"{start:.3f}"]
        cmd += [
            "-i",str(source),"-vn","-map","0:a:0?",
            "-ac","1","-ar","48000","-acodec","pcm_s8","-f","s8","pipe:1"
        ]
        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL, creationflags=NO_WINDOW
        )
        self.send_response(200)
        self.send_header("Content-Type","application/octet-stream")
        self.send_header("X-CCLUA-Format","pcm_s8")
        self.send_header("X-CCLUA-Sample-Rate","48000")
        self.end_headers()
        try:
            assert proc.stdout is not None
            while True:
                chunk = proc.stdout.read(64*1024)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass
        finally:
            if proc.poll() is None:
                proc.terminate()
            try: proc.wait(timeout=2)
            except Exception:
                proc.kill()
    def stream_video(self, source: Path, start: float, cols: int, rows: int, fps: float):
        width, height = cols*2, rows*3
        vf = (
            f"scale={width}:{height}:force_original_aspect_ratio=decrease,"
            f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:black,"
            f"fps={fps:.3f}"
        )
        cmd = [ffmpeg_exe(),"-hide_banner","-loglevel","error"]
        if start > 0:
            cmd += ["-ss",f"{start:.3f}"]
        cmd += [
            "-i",str(source),"-an","-vf",vf,
            "-pix_fmt","rgb24","-f","rawvideo","pipe:1"
        ]
        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL, creationflags=NO_WINDOW
        )
        frame_bytes = width*height*3
        encoded_bytes = cols*rows*3
        self.send_response(200)
        self.send_header("Content-Type","application/octet-stream")
        self.send_header("X-CCLUA-Format","blit-2x3")
        self.send_header("X-CCLUA-Cols",str(cols))
        self.send_header("X-CCLUA-Rows",str(rows))
        self.send_header("X-CCLUA-FPS",f"{fps:.3f}")
        self.send_header("X-CCLUA-Frame-Bytes",str(encoded_bytes))
        self.end_headers()
        try:
            assert proc.stdout is not None
            while True:
                buf = bytearray()
                while len(buf) < frame_bytes:
                    chunk = proc.stdout.read(frame_bytes-len(buf))
                    if not chunk:
                        break
                    buf.extend(chunk)
                if len(buf) != frame_bytes:
                    break
                encoded = encode_frame(bytes(buf),cols,rows)
                self.wfile.write(encoded)
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass
        finally:
            if proc.poll() is None:
                proc.terminate()
            try: proc.wait(timeout=2)
            except Exception:
                proc.kill()

class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

def main() -> int:
    ap = argparse.ArgumentParser(description="CCLUA Theater movie bridge")
    ap.add_argument("--library", type=Path, default=DEFAULT_LIBRARY)
    ap.add_argument("--bind", default=DEFAULT_BIND)
    ap.add_argument("--port", type=int, default=DEFAULT_PORT)
    ap.add_argument("--status", action="store_true")
    args = ap.parse_args()

    cfg = BridgeConfig(args.library,args.bind,max(1,min(65535,args.port)))
    bridge = TheaterBridge(cfg)
    if args.status:
        print(json.dumps({
            "library":str(cfg.library),
            "movies":bridge.catalog(max_age=0),
        },indent=2))
        return 0

    cfg.library.mkdir(parents=True,exist_ok=True)
    server = Server((cfg.bind,cfg.port),Handler)
    server.bridge = bridge  # type: ignore[attr-defined]
    print(f"CCLUA Theater bridge listening on http://{cfg.bind}:{cfg.port}/v1", flush=True)
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

