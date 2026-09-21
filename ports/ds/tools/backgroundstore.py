"""Deduplicate exact background blocks without runtime decompression."""
import hashlib
import json
from pathlib import Path


def pack(output,name,data,shift):
    size=1<<shift
    pages=[]; blocks=[]; seen={}
    for offset in range(0,len(data),size):
        block=bytes(data[offset:offset+size]).ljust(size,b"\0")
        if block not in seen:
            seen[block]=len(blocks); blocks.append(block)
        pages.append(seen[block])
    assert len(blocks)<65536
    encoded=b"".join(blocks)
    (output/"nitro"/(name+".bin")).write_bytes(encoded)
    (output/(name+"store.json")).write_text(json.dumps(dict(shift=shift,pages=pages,bytes=len(data),
        sha256=hashlib.sha256(data).hexdigest(),packedSha256=hashlib.sha256(encoded).hexdigest()),indent=2))
    (output/(name+"store.hpp")).write_text("#pragma once\nnamespace backgroundstore {\n"+
        f"inline constexpr unsigned {name}shift={shift};\ninline constexpr unsigned short {name}pages[]={{"+
        ",".join(map(str,pages))+"};\n}\n")
    print(f"Background {name}: {len(data):,} -> {len(encoded):,} bytes",flush=True)


def read(output,name):
    data=(output/"nitro"/(name+".bin")).read_bytes()
    info=json.loads((output/(name+"store.json")).read_text())
    size=1<<info["shift"]
    assert hashlib.sha256(data).hexdigest()==info["packedSha256"]
    result=b"".join(data[page*size:(page+1)*size] for page in info["pages"])[:info["bytes"]]
    assert hashlib.sha256(result).hexdigest()==info["sha256"]
    return result


def update(output):
    for name,shift in (("world",15),("upperbg",14)):
        if not (output/(name+"store.json")).exists():
            pack(output,name,(output/"nitro"/(name+".bin")).read_bytes(),shift)


if __name__=="__main__": update(Path(__file__).resolve().parents[1]/"generated")
