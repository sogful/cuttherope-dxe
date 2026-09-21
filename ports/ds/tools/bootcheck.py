"""Bounded hardware-probe check in the existing silent libretro harness."""
import ctypes as c
import hashlib
import json
import struct


def check(core,root,directory,path,framebuffer):
    symbols=(root/"build/bootsymbols.txt").read_text().splitlines()
    names=("bootstate","bootfiles","booterror")
    offsets=[int(next(line.split()[0] for line in symbols if line.endswith(" "+name)),16)-0x02000000 for name in names]
    state={}
    for frame in range(1800):
        core.retro_run()
        memory=core.retro_get_memory_data(2)
        size=core.retro_get_memory_size(2)
        assert size==4*1024*1024
        state=dict(zip(names,[struct.unpack("<I",c.string_at(memory+offset,4))[0] for offset in offsets]))
        if state["bootstate"]>=5:
            for _ in range(2): core.retro_run()
            break
    framebuffer().save(directory/"bootcheck.png")
    expected=(root/"generated/bootassets.hpp").read_text().count('{"')
    report=dict(romSha256=hashlib.sha256(path.read_bytes()).hexdigest(),console="DS",muted=True,headless=True,
        mainRamBytes=size,frames=frame+1,**state)
    report["passed"]=state["bootstate"]==5 and state["bootfiles"]==expected and state["booterror"]==0
    (directory/"bootcheck.json").write_text(json.dumps(report,indent=2))
    assert report["passed"],report
    print(f"PASS: hardware probe reaches main, mounts cartridge NitroFS and verifies {expected} asset samples without SD storage")
