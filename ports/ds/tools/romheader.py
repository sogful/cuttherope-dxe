"""Check the DS/DSi homebrew header before distributing a ROM."""
import struct


def crc(data):
    value=0xffff
    for byte in data:
        value^=byte
        for _ in range(8):
            value=(value>>1)^0xa001 if value&1 else value>>1
    return value


def validate(data):
    assert len(data)>=0x4000, "Missing extended ROM header"
    word=lambda offset: struct.unpack_from("<I",data,offset)[0]
    assert data[0x12]==2, "Expected DS+DSi unit code 2, not DS-only or DSi-only"
    assert word(0x234)==0x00030000, "Expected cartridge title ID, not DSiWare"
    assert data[0x0c:0x10]==b"####", "Keep the emulator's homebrew identification"
    assert word(0x84)==0x4000, "Expected full homebrew header reservation"
    assert crc(data[:0x15e])==struct.unpack_from("<H",data,0x15e)[0], "Header CRC mismatch"
    assert crc(data[0xc0:0x15c])==struct.unpack_from("<H",data,0x15c)[0], "Logo CRC mismatch"
    assert word(0x210)==len(data), "Extended ROM size mismatch"
    sections=[]
    for name,offset,limit in (("arm9",0x20,0x02400000),("arm7",0x30,0x02400000),
                              ("arm9i",0x1c0,0x03000000),("arm7i",0x1d0,0x03000000)):
        source,entry,address,size=struct.unpack_from("<4I",data,offset)
        assert size>0 and size%4==0, f"{name}: missing or unaligned section"
        assert source>=0x4000 and source%0x200==0 and source+size<=len(data), f"{name}: invalid ROM range"
        assert 0x02000000<=address<address+size<=limit, f"{name}: invalid RAM range"
        assert any(data[source:source+size]), f"{name}: empty payload"
        if offset<0x40:
            assert address<=entry<address+size, f"{name}: entry outside payload"
        sections.append(dict(name=name,source=source,address=address,size=size))
    for index,section in enumerate(sections):
        for other in sections[index+1:]:
            for start in ("source","address"):
                assert (section[start]+section["size"]<=other[start] or
                        other[start]+other["size"]<=section[start]), f"Overlapping {start}: {section['name']}/{other['name']}"
    start=word(0x20)+word(0x24)-word(0x28)
    assert struct.unpack_from("<4I",data,start)==(0xe3a00301,0xe5800208,0xe3a00013,0xe129f000), "Modern-homebrew startup signature changed"
    assert word(0x1a0)==0x00403000, "ARM7 DSi WRAM mapping does not match the SDK"
    assert word(0x1b8)==0x80040407, "DSi hardware access mask changed"
    return sections
