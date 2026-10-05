import json
import subprocess
import sys
import tempfile
import threading
import urllib.request
from pathlib import Path

ROOT=Path(r"E:\Minecraft\CCLUA-LINUX")
sys.path.insert(0,str(ROOT/"tools"))
from music_import import NO_WINDOW, ffmpeg_exe
from theater_bridge import BridgeConfig, TheaterBridge, Handler, Server

with tempfile.TemporaryDirectory(prefix="cclua-theater-test-") as td:
    library=Path(td)
    movie=library/"Test Feature.mp4"
    cmd=[
        ffmpeg_exe(),"-hide_banner","-loglevel","error","-y",
        "-f","lavfi","-i","testsrc2=size=640x360:rate=12",
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

    cols,rows=144,54
    frame_bytes=cols*rows*3
    with urllib.request.urlopen(
        origin+item["video_url"]+f"?start=0.25&cols={cols}&rows={rows}&fps=12",timeout=20
    ) as r:
        frame=r.read(frame_bytes)
        fmt=r.headers.get("X-CCLUA-Format")
    assert fmt=="blit-2x3"
    assert len(frame)==frame_bytes
    row=frame[:cols*3]
    chars,fg,bg=row[:cols],row[cols:cols*2],row[cols*2:]
    assert len(chars)==len(fg)==len(bg)==cols
    assert all(c in b"0123456789abcdef" for c in fg+bg)

    server.shutdown();server.server_close();thread.join(timeout=2)

print("THEATER_BRIDGE_OK")
print("CATALOG_METADATA_PASS")
print("PCM_48K_STREAM_PASS")
print("BLIT_288X162_FRAME_PASS")
