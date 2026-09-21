import argparse
import struct
from pathlib import Path

from PIL import Image
import banner


def crc(data):
    value=0xffff
    for byte in data:
        value^=byte
        for _ in range(8):
            value=(value>>1)^0xa001 if value&1 else value>>1
    return value


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("rom",type=Path)
    parser.add_argument("--bootcheck",action="store_true")
    args=parser.parse_args()
    data=args.rom.read_bytes()
    offset=struct.unpack_from("<I",data,0x68)[0]
    block=data[offset:offset+0x840]
    assert struct.unpack_from("<H",block)[0]==1
    assert crc(block[0x20:])==struct.unpack_from("<H",block,2)[0]
    title=banner.title.replace(";","\n")+("\nBoot diagnostics" if args.bootcheck else "")
    for language in range(6):
        actual=block[0x240+language*0x100:0x340+language*0x100].decode("utf-16-le").rstrip("\0")
        assert actual==title,(language,actual)
    source=Image.open(banner.root/"assets/icon.png").convert("RGBA")
    palette=struct.unpack_from("<16H",block,0x220)
    decoded=Image.new("RGBA",(32,32))
    for y in range(32):
        for x in range(32):
            index=(y//8*4+x//8)*32+y%8*4+x%8//2
            code=(block[0x20+index]>>(4*(x%2)))&15
            value=palette[code]
            pixel=tuple(((value>>shift)&31)*255//31 for shift in (0,5,10))+(255 if code else 0,)
            expected=source.getpixel((x,y))
            assert (pixel[3]>0)==(expected[3]>0),(x,y)
            if pixel[3]:
                assert all(((expected[channel]>>3)*255//31)==pixel[channel] for channel in range(3)),(x,y,pixel,expected)
            decoded.putpixel((x,y),pixel)
    decoded.save(banner.root/"build/icon-decoded.png")
    print("PASS: six launcher titles, banner CRC, all 1,024 icon pixels and transparency")


if __name__=="__main__": main()
