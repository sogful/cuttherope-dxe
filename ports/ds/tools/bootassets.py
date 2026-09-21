"""Generate bounded first/middle/last read checks for the hardware probe."""
from pathlib import Path


def fingerprint(data):
    value = 2166136261
    for byte in data:
        value = ((value^byte)*16777619)&0xffffffff
    return value


def build(output):
    entries = []
    for path in sorted((output/"nitro").glob("*.bin")):
        size = path.stat().st_size
        count = min(size,4096)
        offsets = sorted({0,(size-count)//2,size-count})
        with path.open("rb") as stream:
            for offset in offsets:
                stream.seek(offset)
                entries.append('{"'+path.name+'",'+f"{size},{offset},{count},{fingerprint(stream.read(count))}u"+'}')
    (output/"bootassets.hpp").write_text("#pragma once\nnamespace bootassets {\n"+
        "struct sample { const char* name; unsigned size,offset,count,hash; };\n"+
        "inline constexpr sample samples[]={"+",".join(entries)+"};\n}\n")


if __name__ == "__main__":
    build(Path(__file__).resolve().parents[1]/"generated")
