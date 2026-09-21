import argparse
import struct
from pathlib import Path

import romheader


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("rom",type=Path)
    args=parser.parse_args()
    data=args.rom.read_bytes()
    sections=romheader.validate(data)
    cases=(("DS-only",0x12,"B",0),("DSi-only",0x12,"B",3),
           ("DSiWare",0x234,"I",0x00030004),("missing ARM9i",0x1cc,"I",0),
           ("missing ARM7i",0x1dc,"I",0),("truncated ARM7i",0x1d0,"I",len(data)),
           ("DS RAM overflow",0x28,"I",0x02400000),("wrong WRAM map",0x1a0,"I",0),
           ("locked hardware mask",0x1b8,"I",0))
    for label,offset,kind,value in cases:
        broken=bytearray(data)
        struct.pack_into("<"+kind,broken,offset,value)
        struct.pack_into("<H",broken,0x15e,romheader.crc(broken[:0x15e]))
        try:
            romheader.validate(broken)
        except AssertionError:
            pass
        else:
            raise AssertionError("Accepted invalid ROM: "+label)
    print(f"PASS: DS/DSi cartridge header, CRCs, four nonoverlapping executable sections, modern-homebrew signature; {len(cases)} malformed headers rejected")
    for section in sections:
        print(f"{section['name']}: ROM 0x{section['source']:08x}, RAM 0x{section['address']:08x}, {section['size']:,} bytes")


if __name__=="__main__": main()
