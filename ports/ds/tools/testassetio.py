import shutil
import re
import json
import subprocess
import uuid
from pathlib import Path

import cachelines

root = Path(__file__).resolve().parents[1]
compiler = shutil.which("g++")
assert compiler, "A native g++ compiler is required"
directory = root / "build" / ("assetio-" + uuid.uuid4().hex)
directory.mkdir()
for logging in (False, True):
    binary = directory / ("logging.exe" if logging else "normal.exe")
    subprocess.run([compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                    *(["-DDS_LOGGING"] if logging else []), "-I" + str(root / "include"),
                    str(root / "tests/assetio.cpp"), str(root / "source/gamelog.cpp"), "-o", str(binary)], check=True)
    subprocess.run([str(binary), str(directory), str(directory / "fixture.bin")], check=True)
log = (directory / "game-0001.log").read_text()
for reason in ("header.eof", "header.kind", "output.capacity", "flags.eof", "token.eof", "match.eof", "match.distance", "match.length"):
    assert "reason=" + reason in log, reason
assert re.search(r"wanted=16 got=9 eof=[1-9][0-9]* error=0", log)
assert "asset.seek.failed name=missing" in log
assert "header=00000010 consumed=1" in log
assert "produced=1 declared=2 capacity=32 length=3 distance=1" in log
assert max(map(len, log.splitlines())) < 768
layout = "\n".join(f"{0x02000000 + index * 0x2000:08x} 00001000 b {name}" for index, name in enumerate(cachelines.buffers))
assert len(cachelines.validate(layout)) == len(cachelines.buffers)
for broken in (layout.replace("02000000", "02000014"), layout.replace("00001000", "00001001", 1),
               layout + "\n02000001 00000001 b frontend::captured"):
    try:
        cachelines.validate(broken)
    except AssertionError:
        pass
    else:
        raise AssertionError("Unsafe cache layout accepted")
print("PASS: durable asset error records and final-link cache-line regression checks")

binary = directory / "packed.exe"
subprocess.run([compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-I" + str(root / "include"),
                str(root / "tests/packed.cpp"), "-o", str(binary)], check=True)
pages = json.loads((root / "generated/menumanifest.json").read_text())["pages"]
catalog = (root / "generated/nitro/menu.bin").read_bytes()
for first in range(0, len(pages), 64):
    batch = pages[first:first + 64]
    files = [root / "generated" / (page["name"] + ".lz") for page in batch]
    results = subprocess.check_output([str(binary), *map(str, files)], text=True).splitlines()
    assert len(results) == len(batch)
    for page, path, result in zip(batch, files, results):
        assert int(result.split()[0]) == page["bytes"]
        start = page["offset"] + page["palettebytes"]
        assert catalog[start:start + page["compressed"]] == path.read_bytes()
print(f"PASS: all {len(pages)} packed pages agree across normal, diagnostic and unpack decoders and match the ROM catalog")
