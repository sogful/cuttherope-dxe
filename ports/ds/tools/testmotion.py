"""Exact comparison against the retained per-background shadow movie."""
import argparse
import json
import struct
from pathlib import Path

import numpy as np
from uppermotion import unpack,steps,keyinterval
import backgroundstore


def apply(data,offset,pixels):
    while True:
        start=int.from_bytes(data[offset:offset+2],"little"); offset+=2
        if start==65535: return
        count=int.from_bytes(data[offset:offset+2],"little"); offset+=2
        pixels[start:start+count]=np.frombuffer(data,dtype=np.uint8,count=count,offset=offset)
        offset+=count


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("baseline",type=Path)
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    output=root/"generated"
    old=(args.baseline/"uppermotion.bin").read_bytes()
    previous=json.loads((args.baseline/"uppermanifest.json").read_text())
    new=(output/"nitro/uppermotion.bin").read_bytes()
    current=json.loads((output/"uppermanifest.json").read_text())
    backgrounds=backgroundstore.read(output,"upperbg")
    entries=steps+steps//keyinterval
    index=struct.unpack_from("<"+"I"*entries,new)
    samples=[]
    codes=np.frombuffer(unpack(memoryview(new)[index[steps]:]),dtype=np.uint8).copy()
    for frame in range(steps):
        if frame: apply(new,index[frame]+4,codes)
        samples.append(codes.copy())
    checked=0
    for scene,offset in enumerate(previous["motionOffsets"]):
        if offset<0: continue
        tableoffset=current["motionOffsets"][scene]
        table=np.frombuffer(new,dtype=np.uint8,count=current["motionTableBytes"],offset=tableoffset).reshape(256,32)
        base=np.frombuffer(backgrounds,dtype=np.uint8,count=49152,offset=current["backgrounds"][scene][0])
        oldindex=struct.unpack_from("<"+"I"*entries,old,offset)
        pixels=np.frombuffer(unpack(memoryview(old)[oldindex[steps]:]),dtype=np.uint8).copy()
        for frame in range(steps):
            if frame: apply(old,oldindex[frame],pixels)
            assert np.array_equal(pixels,table[base,samples[frame]]),(scene,frame)
            checked+=1
        print("Exact shadow scene",scene,flush=True)
    print(f"PASS: {checked:,} complete shadow frames match the retained ROM pixel-for-pixel")


if __name__=="__main__": main()
