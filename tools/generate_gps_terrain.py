#!/usr/bin/env python3
import argparse, gzip, io, math, os, struct, zlib
import nbtlib

def u8(f): return struct.unpack(">B", f.read(1))[0]
def i8(f): return struct.unpack(">b", f.read(1))[0]
def i16(f): return struct.unpack(">h", f.read(2))[0]
def i32(f): return struct.unpack(">i", f.read(4))[0]
def i64(f): return struct.unpack(">q", f.read(8))[0]
def read_string(f):
    n=struct.unpack(">H",f.read(2))[0]
    return f.read(n).decode("utf-8","replace")

def read_payload(f,t):
    if t==1: return i8(f)
    if t==2: return i16(f)
    if t==3: return i32(f)
    if t==4: return i64(f)
    if t==5: return struct.unpack(">f",f.read(4))[0]
    if t==6: return struct.unpack(">d",f.read(8))[0]
    if t==7: return f.read(i32(f))
    if t==8: return read_string(f)
    if t==9:
        et=u8(f); return [read_payload(f,et) for _ in range(i32(f))]
    if t==10:
        out={}
        while True:
            ct=u8(f)
            if ct==0: return out
            out[read_string(f)]=read_payload(f,ct)
    if t==11: return [i32(f) for _ in range(i32(f))]
    if t==12: return [i64(f) for _ in range(i32(f))]
    raise ValueError(f"unsupported NBT tag {t}")

def read_nbt(data):
    parsed=nbtlib.File.parse(io.BytesIO(data))
    return parsed

class RegionCache:
    def __init__(self, world):
        self.world=world
        self.files={}
        self.chunks={}
    def _region(self,rx,rz):
        key=(rx,rz)
        if key in self.files: return self.files[key]
        path=os.path.join(self.world,"region",f"r.{rx}.{rz}.mca")
        if not os.path.exists(path):
            self.files[key]=None; return None
        f=open(path,"rb"); header=f.read(4096)
        self.files[key]=(f,header)
        return self.files[key]
    def chunk(self,cx,cz):
        key=(cx,cz)
        if key in self.chunks: return self.chunks[key]
        rx,rz=cx//32,cz//32
        reg=self._region(rx,rz)
        if not reg:
            self.chunks[key]=None; return None
        f,header=reg
        idx=(cx%32)+(cz%32)*32
        ent=header[idx*4:(idx+1)*4]
        off=int.from_bytes(ent[:3],"big")
        if off==0:
            self.chunks[key]=None; return None
        f.seek(off*4096)
        ln=struct.unpack(">I",f.read(4))[0]
        comp=u8(f); blob=f.read(ln-1)
        if comp==1: raw=gzip.decompress(blob)
        elif comp==2: raw=zlib.decompress(blob)
        elif comp==3: raw=blob
        else: raise ValueError(f"unsupported compression {comp}")
        self.chunks[key]=read_nbt(raw)
        return self.chunks[key]

AIR={"minecraft:air","minecraft:cave_air","minecraft:void_air"}

def palette_name(entry):
    return entry.get("Name","minecraft:air") if isinstance(entry,dict) else "minecraft:air"

def section_blocks(section):
    bs=section.get("block_states") or section.get("BlockStates")
    if not isinstance(bs,dict): return None
    palette=bs.get("palette") or bs.get("Palette") or []
    if not palette: return None
    names=[palette_name(x) for x in palette]
    if len(names)==1:
        return lambda x,y,z: names[0]
    data=bs.get("data")
    if data is None: data=bs.get("Data")
    if data is None or len(data)==0: return None
    bits=max(4,(len(names)-1).bit_length())
    per=64//bits
    mask=(1<<bits)-1
    def get(x,y,z):
        idx=(y*16+z)*16+x
        li=idx//per; shift=(idx%per)*bits
        if li>=len(data): return "minecraft:air"
        value=data[li] & 0xffffffffffffffff
        pi=(value>>shift)&mask
        return names[pi] if pi<len(names) else "minecraft:air"
    return get

def top_block(chunk,lx,lz):
    if not chunk: return "minecraft:void_air", -64
    sections=chunk.get("sections") or chunk.get("Sections") or []
    ordered=sorted((s for s in sections if isinstance(s,dict)),
                   key=lambda s:int(s.get("Y",-99)), reverse=True)
    for s in ordered:
        get=section_blocks(s)
        if not get: continue
        sy=int(s.get("Y",0))
        for ly in range(15,-1,-1):
            name=get(lx,ly,lz)
            if name not in AIR:
                return name, sy*16+ly
    return "minecraft:void_air",-64

# CC:Tweaked blit digits: 0 white ... f black.
def block_color(name,height):
    n=name.split(":",1)[-1]
    if "water" in n: return "b"
    if any(k in n for k in ("grass","moss","leaves","vine","azalea")): return "d"
    if any(k in n for k in ("sand","sandstone","hay","bamboo","yellow_")): return "4"
    if any(k in n for k in ("snow","quartz","white_","birch")): return "0"
    if any(k in n for k in ("dirt","mud","podzol","rooted","brown_","spruce","oak","log","planks")): return "c"
    if any(k in n for k in ("lava","magma","red_","nether_wart")): return "e"
    if any(k in n for k in ("cyan_","prismarine")): return "9"
    if any(k in n for k in ("light_blue_","packed_ice","blue_ice")): return "3"
    if any(k in n for k in ("blue_","lapis")): return "b"
    if any(k in n for k in ("lime_","slime")): return "5"
    if any(k in n for k in ("green_","cactus")): return "d"
    if any(k in n for k in ("orange_","copper")): return "1"
    if any(k in n for k in ("purple_","amethyst")): return "a"
    if any(k in n for k in ("magenta_","pink_")): return "6"
    if any(k in n for k in ("black_","coal","obsidian")): return "f"
    if any(k in n for k in ("gray_","deepslate","blackstone","bedrock")): return "7"
    if any(k in n for k in ("stone","cobble","brick","iron","andesite","diorite","granite","concrete")): return "8"
    return "7" if height<55 else "8"

def generate(world,cx,cz,radius):
    rc=RegionCache(world)
    rows=[]; heights=[]
    for z in range(cz-radius,cz+radius+1):
        line=[]; hline=[]
        for x in range(cx-radius,cx+radius+1):
            chunk=rc.chunk(x//16,z//16)
            name,h=top_block(chunk,x%16,z%16)
            line.append(block_color(name,h)); hline.append(h)
        rows.append("".join(line)); heights.append(hline)
    for item in rc.files.values():
        if item: item[0].close()
    return rows,heights

def write_lua(path,cx,cz,radius,rows,heights):
    os.makedirs(os.path.dirname(path),exist_ok=True)
    with open(path,"w",newline="\n") as f:
        f.write("return {\n")
        f.write(f"  schema=1, center_x={cx}, center_z={cz}, radius={radius},\n")
        f.write(f"  min_x={cx-radius}, max_x={cx+radius}, min_z={cz-radius}, max_z={cz+radius},\n")
        f.write(f"  width={len(rows[0])}, height={len(rows)}, rows={{\n")
        for row in rows: f.write(f'    "{row}",\n')
        f.write("  },\n}\n")

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--world",required=True)
    ap.add_argument("--output",required=True)
    ap.add_argument("--center-x",type=int,default=20)
    ap.add_argument("--center-z",type=int,default=15)
    ap.add_argument("--radius",type=int,default=48)
    a=ap.parse_args()
    rows,heights=generate(a.world,a.center_x,a.center_z,a.radius)
    write_lua(a.output,a.center_x,a.center_z,a.radius,rows,heights)
    print(f"wrote {len(rows[0])}x{len(rows)} block terrain cache to {a.output}")

if __name__=="__main__": main()
