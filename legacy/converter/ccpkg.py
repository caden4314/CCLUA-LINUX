from __future__ import annotations
import argparse, json, re, shutil, subprocess, tarfile, tempfile
from collections import Counter
from pathlib import Path

EXT_LANG = {
    ".lua":"lua", ".sh":"shell", ".bash":"shell", ".py":"python",
    ".c":"c", ".h":"c", ".cc":"cpp", ".cpp":"cpp", ".cxx":"cpp",
    ".rs":"rust", ".go":"go", ".pl":"perl", ".rb":"ruby",
}
SCRIPT_INTERPRETERS = {
    "lua":"lua", "bash":"shell", "sh":"shell", "dash":"shell",
    "python":"python", "python3":"python", "perl":"perl", "ruby":"ruby",
}
IGNORED_DIRS={".git",".pc","node_modules","build"}

def parse_deb822(text:str)->list[dict[str,str]]:
    stanzas=[]; cur={}; key=None
    for raw in text.splitlines()+[""]:
        if not raw.strip():
            if cur: stanzas.append(cur); cur={}; key=None
            continue
        if raw[:1].isspace() and key:
            cur[key]+="\n"+raw[1:]; continue
        if raw.startswith("#") or ":" not in raw: continue
        key,value=raw.split(":",1); key=key.strip()
        cur[key]=value.strip()
    return stanzas

def package_metadata(root:Path)->dict:
    control=root/"debian"/"control"; changelog=root/"debian"/"changelog"
    meta={"source":root.name,"version":"unknown","binaries":[]}
    if control.exists():
        s=parse_deb822(control.read_text(errors="replace"))
        if s:
            meta["source"]=s[0].get("Source",meta["source"])
            meta["build_depends"]=s[0].get("Build-Depends","")
            meta["binaries"]=[x.get("Package") for x in s[1:] if x.get("Package")]
    if changelog.exists():
        m=re.match(r"([^ ]+) \(([^)]+)\)",changelog.read_text(errors="replace"))
        if m: meta["source"],meta["version"]=m.groups()
    return meta

def scan_tree(root:Path)->dict:
    counts=Counter(); scripts=Counter(); files=[]
    for p in root.rglob("*"):
        if not p.is_file(): continue
        rel=p.relative_to(root)
        if any(part in IGNORED_DIRS for part in rel.parts): continue
        lang=EXT_LANG.get(p.suffix.lower())
        if lang: counts[lang]+=1
        try:
            if p.stat().st_size < 1024*1024:
                first=p.open("rb").readline(256).decode("utf-8","ignore").strip()
                if first.startswith("#!"):
                    interp=Path(first.split()[0][2:]).name
                    if interp=="env" and len(first.split())>1: interp=first.split()[1]
                    if interp in SCRIPT_INTERPRETERS: scripts[SCRIPT_INTERPRETERS[interp]]+=1
        except OSError: pass
        files.append(str(rel).replace("\\","/"))
    return {"languages":dict(counts),"scripts":dict(scripts),"file_count":len(files),"files":files}

def classify(meta:dict, scan:dict)->dict:
    langs=Counter(scan["languages"]); scripts=Counter(scan["scripts"])
    score=langs+scripts
    deps=meta.get("build_depends","").lower()
    reasons=[]; backend="data"; confidence=0.70
    if score["lua"]:
        backend="lua-native"; confidence=.98
    elif score["shell"] and not sum(score[x] for x in ("c","cpp","rust","go")):
        backend="shell"; confidence=.90
    elif score["python"] and not sum(score[x] for x in ("c","cpp","rust","go")):
        backend="python"; confidence=.86
    elif score["c"] or score["cpp"] or any(x in deps for x in ("gcc","g++","cmake","meson")):
        backend="wasm-aot-lua"; confidence=.80
    elif score["rust"]:
        backend="wasm-aot-lua"; confidence=.75
    elif score["go"]:
        backend="wasm-aot-lua"; confidence=.68
    elif score["perl"] or score["ruby"]:
        backend="interpreter-port"; confidence=.45
    if any(x in meta["source"].lower() for x in ("linux","grub","systemd","udev","kmod")):
        reasons.append("requires privileged Linux kernel/device semantics")
        confidence=min(confidence,.35)
    return {"backend":backend,"confidence":confidence,"reasons":reasons,
            "language_score":dict(score)}

def compatibility(meta:dict, scan:dict, plan:dict)->dict:
    blockers=[]
    names=" ".join(scan.get("files",[])).lower()
    deps=meta.get("build_depends","").lower()
    checks={
      "kernel_api": any(x in names for x in ("/proc/","/sys/","ioctl","netlink")),
      "native_asm": any(x in names for x in (".s",".asm")),
      "gui": any(x in deps for x in ("x11","gtk","qtbase","wayland")),
      "threads": any(x in deps for x in ("pthread","libomp")),
    }
    if checks["kernel_api"]: blockers.append("Linux-specific kernel API usage needs a CCUbuntu shim")
    if checks["native_asm"]: blockers.append("native assembly requires replacement")
    if checks["gui"]: blockers.append("GUI dependency is outside console target")
    if checks["threads"]: blockers.append("threading maps to cooperative CC tasks")
    return {"checks":checks,"blockers":blockers,"automatic":len(blockers)==0}

def emit_shell_wrapper(src:Path,dst:Path):
    text=src.read_text(errors="replace")
    lines=text.splitlines()
    if lines and lines[0].startswith("#!"): lines=lines[1:]
    payload=json.dumps("\n".join(lines))
    lua=("local shellrt=require('ccubuntu.shell')\n"
         "local script="+payload+"\n"
         "return shellrt.run_script(script,{...})\n")
    dst.parent.mkdir(parents=True,exist_ok=True); dst.write_text(lua)

def build_package(root:Path,outdir:Path)->Path:
    meta=package_metadata(root); scan=scan_tree(root); plan=classify(meta,scan)
    compat=compatibility(meta,scan,plan)
    pkgdir=outdir/f"{meta['source']}_{meta['version']}"
    if pkgdir.exists(): shutil.rmtree(pkgdir)
    (pkgdir/"payload").mkdir(parents=True)
    backend=plan["backend"]; converted=[]
    if backend=="lua-native":
        for p in root.rglob("*.lua"):
            if "debian" in p.parts: continue
            rel=p.relative_to(root); dest=pkgdir/"payload"/"usr"/"lib"/meta["source"]/rel
            dest.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(p,dest); converted.append(str(rel))
    elif backend=="shell":
        for p in root.rglob("*"):
            if not p.is_file(): continue
            first=p.open("rb").readline(128).decode("utf-8","ignore")
            if p.suffix in (".sh",".bash") or "sh" in first[:40]:
                rel=p.relative_to(root); dest=pkgdir/"payload"/"usr"/"lib"/meta["source"]/(str(rel)+".lua")
                emit_shell_wrapper(p,dest); converted.append(str(rel))
    elif backend=="data":
        for p in root.rglob("*"):
            if p.is_file() and "debian" not in p.parts:
                rel=p.relative_to(root); dest=pkgdir/"payload"/"usr"/"share"/meta["source"]/rel
                dest.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(p,dest); converted.append(str(rel))
    manifest={"format":1,"target":"ccubuntu-jammy","package":meta,"scan":scan,
              "plan":plan,"compatibility":compat,"converted":converted,
              "status":"built" if backend in ("lua-native","shell","data") else "needs-backend"}
    (pkgdir/"manifest.json").write_text(json.dumps(manifest,indent=2))
    return pkgdir

def main():
    ap=argparse.ArgumentParser(prog="ccpkg",description="Ubuntu source -> CCUbuntu Lua package converter")
    sub=ap.add_subparsers(dest="cmd",required=True)
    p=sub.add_parser("inspect"); p.add_argument("source",type=Path)
    p=sub.add_parser("build"); p.add_argument("source",type=Path); p.add_argument("-o","--out",type=Path,default=Path("repo"))
    a=ap.parse_args(); root=a.source.resolve()
    meta=package_metadata(root); scan=scan_tree(root); plan=classify(meta,scan)
    if a.cmd=="inspect":
        print(json.dumps({"package":meta,"scan":scan,"plan":plan,"compatibility":compatibility(meta,scan,plan)},indent=2))
    else:
        result=build_package(root,a.out.resolve()); print(result)
        print((result/"manifest.json").read_text())

if __name__=="__main__": main()
