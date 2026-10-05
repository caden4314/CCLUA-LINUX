import json
import json
import subprocess
import sys
import tempfile
import threading
import urllib.request
from pathlib import Path

import numpy as np

ROOT=Path(r"E:\Minecraft\CCLUA-LINUX")
sys.path.insert(0,str(ROOT/"tools"))
from music_import import NO_WINDOW, ffmpeg_exe
from theater_bridge import (
    BridgeConfig, TheaterBridge, Handler, Server,
    PALETTE, HEX, encode_frame, encode_texel,
)

# The optimized vector encoder must be bit-for-bit equivalent to the original
# per-cell pixelbox algorithm for palette-colour source pixels.
rng=np.random.default_rng(4314)
cols_ref,rows_ref=13,7
palette_idx=rng.integers(0,16,size=(rows_ref*3,cols_ref*2),dtype=np.uint8)
rgb=PALETTE[palette_idx].astype(np.uint8).tobytes()
fast=encode_frame(rgb,cols_ref,rows_ref)
ref=bytearray()
for cy in range(rows_ref):
    chars=bytearray(cols_ref);fgs=bytearray(cols_ref);bgs=bytearray(cols_ref)
    for cx in range(cols_ref):
        py,px=cy*3,cx*2
        vals=[
            int(palette_idx[py,px]),int(palette_idx[py,px+1]),
            int(palette_idx[py+1,px]),int(palette_idx[py+1,px+1]),
            int(palette_idx[py+2,px]),int(palette_idx[py+2,px+1]),
        ]
        ch,fg,bg=encode_texel(vals)
        chars[cx]=ch;fgs[cx]=HEX[fg];bgs[cx]=HEX[bg]
    ref.extend(chars);ref.extend(fgs);ref.extend(bgs)
assert fast==bytes(ref),"vectorized encoder changed pixelbox output"

with tempfile.TemporaryDirectory(prefix="cclua-theater-test-") as td:
    library=Path(td)
    movie=library/"Test Feature.mp4"
    cmd=[
        ffmpeg_exe(),"-hide_banner","-loglevel","error","-y",
        "-f","lavfi","-i","testsrc2=size=640x360:rate=20",
        "-f","lavfi","-i","sine=frequency=440:sample_rate=48000",
        "-t","2","-pix_fmt","yuv420p","-c:v","libx264","-c:a","aac",str(movie)
    ]
    subprocess.run(cmd,check=True,creationflags=NO_WINDOW)

    bridge=TheaterBridge(BridgeConfig(library,"127.0.0.1",0))
    server=Server(("127.0.0.1",0),Handler)
    server.bridge=bridge
    port=server.server_address[1]
    thread=threading.Thread(target=server.serve_forever,daemon=True)
    thread.start()
    origin=f"http://127.0.0.1:{port}"
    base=origin+"/v1"

    health=json.load(urllib.request.urlopen(base+"/health",timeout=5))
    assert health["ok"] and health["catalog_count"]==1

    cat=json.load(urllib.request.urlopen(base+"/catalog",timeout=5))
    assert len(cat["movies"])==1
    item=cat["movies"][0]
    assert item["title"]=="Test Feature"
    assert item["duration"] and item["duration"]>1.5

    with urllib.request.urlopen(origin+item["audio_url"]+"?start=0.25",timeout=10) as r:
        audio=r.read(8192)
    assert len(audio)==8192

    cols,rows=167,55
    frame_bytes=cols*rows*3
    with urllib.request.urlopen(
        origin+item["video_url"]+f"?start=0.25&cols={cols}&rows={rows}&fps=20",timeout=20
    ) as r:
        frame=r.read(frame_bytes)
        fmt=r.headers.get("X-CCLUA-Format")
        out_cols=r.headers.get("X-CCLUA-Cols")
        out_rows=r.headers.get("X-CCLUA-Rows")
        out_fps=r.headers.get("X-CCLUA-FPS")
    assert fmt=="blit-2x3"
    assert out_cols=="167"
    assert out_rows=="55"
    assert out_fps=="20.000"
    assert len(frame)==frame_bytes
    row=frame[:cols*3]
    chars,fg,bg=row[:cols],row[cols:cols*2],row[cols*2:]
    assert len(chars)==len(fg)==len(bg)==cols
    assert all(c in b"0123456789abcdef" for c in fg+bg)

    server.shutdown();server.server_close();thread.join(timeout=2)

print("THEATER_BRIDGE_OK")
print("CATALOG_METADATA_PASS")
print("PCM_48K_STREAM_PASS")
print("BLIT_FULL_WALL_334X165_20FPS_FRAME_PASS")
print("VECTORIZED_ENCODER_EQUIVALENCE_PASS")
