"""Exact software-shadow raster, stored as sparse pixel changes for the ARM9.

The 75-second authored rotation is sampled every five game updates. Keyframes
bound seeks to five seconds of sparse patches. No extra permanent frame buffer.
"""
import math
import struct
import numpy as np

steps=900
interval=5
keyinterval=60


def unpack(data):
    result=bytearray(); cursor=4
    size=int.from_bytes(data[1:4],"little")
    while len(result)<size:
        flags=data[cursor]; cursor+=1
        for bit in range(7,-1,-1):
            if len(result)>=size: break
            if flags&(1<<bit):
                a,b=data[cursor:cursor+2]; cursor+=2
                distance=((a&15)<<8)+b+1
                for _ in range((a>>4)+3): result.append(result[-distance])
            else:
                result.append(data[cursor]); cursor+=1
    return result


def patch(previous,current):
    changed=np.flatnonzero(previous!=current)
    if not len(changed): return b"\xff\xff"
    breaks=np.flatnonzero(np.diff(changed)>4)
    starts=changed[np.r_[0,breaks+1]]
    ends=changed[np.r_[breaks,len(changed)-1]]+1
    result=bytearray()
    for start,end in zip(starts,ends):
        result.extend(struct.pack("<HH",int(start),int(end-start)))
        result.extend(current[start:end].tobytes())
    result.extend(b"\xff\xff")
    return result


def bake(output,manifest,backgrounds,records,palettes,lookups,spans):
    item=next(item for item in manifest["sprites"] if item["name"]=="shadow")
    page=manifest["pages"][item["page"]]
    source=np.frombuffer(unpack((output/(page["name"]+".lz")).read_bytes()),dtype=np.uint8)
    colors=np.frombuffer((output/(page["name"]+"palette.bin")).read_bytes(),dtype="<u2").astype(np.uint32)
    scale=1781*2*(192/1440)/256
    yy,xx=np.mgrid[0:192,0:256]
    mask=(xx>=np.asarray(spans)[:,0,None])&(xx<np.asarray(spans)[:,1,None])
    samples=[]
    for step in range(steps):
        angle=4096+(step*interval)*32768//4500
        radians=angle*2*math.pi/32768
        cosine,sine=math.cos(radians),math.sin(radians)
        tx,ty=round(cosine/scale*65536),round(sine/scale*65536)
        ux=round((-128*cosine-96*sine-round(item["ox"]*scale))/scale*65536)+(tx+ty)//2
        uy=round((128*sine-96*cosine-round(item["oy"]*scale))/scale*65536)+(-ty+tx)//2
        columns=(ux+xx*tx+yy*ty)>>16
        rows=(uy-xx*ty+yy*tx)>>16
        assert columns.min()>=0 and columns.max()<256 and rows.min()>=0 and rows.max()<256
        samples.append(source[rows*256+columns])
    entries=[]
    with (output/"nitro/uppermotion.bin").open("wb") as stream:
        for ident,(offset,height,profile) in enumerate(records[:20]):
            if ident==2:  # Authored picker background has no shadow.
                entries.append(-1); continue
            print("Upper shadow playback",ident+1,"/ 20",flush=True)
            base=np.frombuffer(backgrounds[offset:offset+49152],dtype=np.uint8).reshape(192,256)
            target=palettes[profile].astype(np.uint32)
            table=np.empty((256,256),dtype=np.uint8)
            for pixel in range(256):
                alpha=pixel>>3
                rgb=colors[pixel&7]
                mixed=((((rgb&0x7c1f)*(alpha+1)+(target&0x7c1f)*(31-alpha))>>5)&0x7c1f)|((((rgb&0x3e0)*(alpha+1)+(target&0x3e0)*(31-alpha))>>5)&0x3e0)
                table[pixel]=lookups[profile][mixed] if alpha else np.arange(256,dtype=np.uint8)
            index=stream.tell(); entries.append(index)
            stream.write(bytes(steps*4))
            offsets=[]; previous=None
            for step,sample in enumerate(samples):
                current=np.where(mask,base,table[sample,base]).astype(np.uint8).ravel()
                offsets.append(stream.tell())
                stream.write(current.tobytes() if step%keyinterval==0 else patch(previous,current))
                previous=current
            end=stream.tell(); stream.seek(index)
            stream.write(struct.pack("<"+"I"*steps,*offsets)); stream.seek(end)
    return entries
