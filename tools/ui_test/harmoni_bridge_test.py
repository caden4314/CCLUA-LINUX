from __future__ import annotations

import ctypes
import json
import shutil
import socket
import struct
import sys
import tempfile
import threading
import time
import urllib.request
import wave
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))

from harmoni_cc_bridge import (
    BridgeConfig,
    HarmoniBridge,
    STATE_DONE,
    STATE_READY,
    STATE_STABLE,
    STATE_WRITING,
)


def make_wav(path: Path, seconds: float = 0.25) -> None:
    rate = 48000
    frames = int(rate * seconds)
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(b"".join(struct.pack("<h", 0) for _ in range(frames)))


def hold_exclusive(path: Path, ready: threading.Event, release: threading.Event) -> None:
    if sys.platform != "win32":
        ready.set()
        release.wait(5)
        return

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    CreateFileW = kernel32.CreateFileW
    CloseHandle = kernel32.CloseHandle
    CreateFileW.argtypes = [
        ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32,
        ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p,
    ]
    CreateFileW.restype = ctypes.c_void_p
    GENERIC_WRITE = 0x40000000
    OPEN_EXISTING = 3
    FILE_ATTRIBUTE_NORMAL = 0x80
    INVALID = ctypes.c_void_p(-1).value

    handle = CreateFileW(
        str(path), GENERIC_WRITE, 0, None,
        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, None,
    )
    if handle == INVALID:
        raise OSError(ctypes.get_last_error(), "exclusive writer CreateFileW failed")
    try:
        ready.set()
        release.wait(5)
    finally:
        CloseHandle(handle)


def state_for(bridge: HarmoniBridge, path: Path) -> str:
    return bridge.records[str(path.resolve()).lower()]["state"]


root = Path(tempfile.mkdtemp(prefix="cclua-harmoni-test-"))
try:
    source = root / "source"
    cache = root / "cache"
    source.mkdir()

    with socket.socket(socket.AF_INET,socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1",0))
        test_port=sock.getsockname()[1]

    cfg = BridgeConfig(
        source=source,
        cache=cache,
        stable_seconds=0.6,
        poll_seconds=0.05,
        min_age_seconds=0.0,
        auto_convert=False,
        retry_seconds=2.0,
        http_enabled=True,
        http_bind="127.0.0.1",
        http_port=test_port,
    )
    bridge = HarmoniBridge(cfg)

    # Case 1: a file whose size/mtime is actively moving.
    moving = source / "moving.wav"
    make_wav(moving)
    bridge.scan()
    assert state_for(bridge, moving) == STATE_WRITING

    with moving.open("ab") as h:
        for _ in range(3):
            h.write(b"\x00\x00" * 128)
            h.flush()
            bridge.scan()
            assert state_for(bridge, moving) in (STATE_WRITING, STATE_STABLE)
            time.sleep(0.15)

    # The moving file was intentionally damaged by appending bytes, so don't
    # require it to become READY. The important assertion is that it never did
    # while bytes were changing.

    # Case 2: valid audio stops changing but is still held open exclusively.
    locked = source / "locked.wav"
    make_wav(locked)
    bridge.scan()
    time.sleep(0.7)

    ready = threading.Event()
    release = threading.Event()
    t = threading.Thread(target=hold_exclusive, args=(locked, ready, release), daemon=True)
    t.start()
    assert ready.wait(2)

    bridge.scan()
    assert state_for(bridge, locked) == STATE_WRITING, state_for(bridge, locked)

    release.set()
    t.join(2)
    time.sleep(0.7)
    bridge.scan()
    assert state_for(bridge, locked) == STATE_READY, state_for(bridge, locked)

    # Conversion publishes a validated DFPWM artifact and DONE must remain
    # sticky while the source identity is unchanged.
    rec = bridge.records[str(locked.resolve()).lower()]
    bridge.convert_record(rec)
    assert state_for(bridge, locked) == STATE_DONE
    output = Path(rec["output"])
    assert output.is_file() and output.stat().st_size > 0

    bridge.scan()
    assert state_for(bridge, locked) == STATE_DONE

    # Read-only local HTTP API: catalog + complete stream + byte ranges.
    bridge.start_http()
    try:
        base=f"http://127.0.0.1:{test_port}/v1"
        with urllib.request.urlopen(base+"/health",timeout=3) as response:
            health=json.loads(response.read().decode("utf-8"))
        assert health["ok"] is True
        assert health["catalog_count"]==1

        with urllib.request.urlopen(base+"/catalog",timeout=3) as response:
            catalog=json.loads(response.read().decode("utf-8"))
        assert catalog["count"]==1
        track=catalog["tracks"][0]
        assert track["id"]==rec["id"]
        assert track["stream_url"].endswith(f"/tracks/{rec['id']}.dfpwm")
        assert track["pcm_stream_url"].endswith(f"/tracks/{rec['id']}.pcm")
        assert track["preferred_format"]=="pcm_s8"

        with urllib.request.urlopen(track["stream_url"],timeout=3) as response:
            body=response.read()
        assert body==output.read_bytes()

        with urllib.request.urlopen(track["pcm_stream_url"],timeout=3) as response:
            pcm=response.read()
            assert response.headers.get("X-CCLUA-Audio-Format")=="pcm_s8"
            assert response.headers.get("X-CCLUA-Sample-Rate")=="48000"
        assert len(pcm)>=11000
        assert set(pcm)=={0}

        with urllib.request.urlopen(track["pcm_stream_url"]+"?start=0.10",timeout=3) as response:
            seeked=response.read()
        assert 6000<=len(seeked)<len(pcm)

        with urllib.request.urlopen(track["pcm_stream_url"]+"?start=0&seconds=0.05",timeout=3) as response:
            segmented=response.read()
            assert response.headers.get("X-CCLUA-Segment-Seconds")=="1.000"
        # Server enforces a one-second minimum segment to avoid request churn.
        assert 11000<=len(segmented)<=13000

        req=urllib.request.Request(track["stream_url"],headers={"Range":"bytes=2-9"})
        with urllib.request.urlopen(req,timeout=3) as response:
            partial=response.read()
            assert response.status==206
            assert response.headers.get("Accept-Ranges")=="bytes"
        assert partial==output.read_bytes()[2:10]
    finally:
        bridge.stop_http()

    print("HARMONI_BRIDGE_OK")
    print("LOCK_DETECTION", "PASS")
    print("STABLE_TO_READY", "PASS")
    print("DFPWM_CONVERSION", output.stat().st_size)
    print("DONE_STICKY", "PASS")
    print("HTTP_CATALOG_STREAM_RANGE", "PASS")
    print("PCM_48K_STREAM_SEEK", "PASS")
finally:
    shutil.rmtree(root, ignore_errors=True)
