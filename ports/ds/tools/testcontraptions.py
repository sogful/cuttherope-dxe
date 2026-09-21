"""Replay independently exported C# DJ/Spooky traces, including actual input coordinates."""
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
fixtures = root.parent / "roblox/tests"
binary = root / "build/contraptionstest.exe"
subprocess.run([shutil.which("g++"), "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-msse2", "-mfpmath=sse", "-ffp-contract=off",
    "-I"+str(root/"include"), "-I"+str(root/"generated"),
    *(str(root/"source"/name) for name in ("simulation.cpp","mechanics.cpp","advanced.cpp","contraptions.cpp","levelstore.cpp")),
    str(root/"tests/contraptions.cpp"), "-o",str(binary)],check=True)
subprocess.run([str(binary)],check=True)
runs, hashes, failures = [], {}, []
array = lambda s: json.loads(s.replace("{","[").replace("}","]"))
for group, box in (("Disc",11),("Ghost",12)):
    for fixture in sorted(fixtures.glob(group+"GoldenData[0-9]*.luau")):
        hashes[fixture.name] = hashlib.sha256(fixture.read_bytes()).hexdigest()
        data = fixture.read_text().split("return ",1)[1].strip()[1:-1]
        pattern = r'\{pack=11,level=(\d+),action="(\w+)",actions=(.*?),samples=(.*)\}' if box==11 else r'\{level=(\d+),mode=(\d+),actions=(.*?),samples=(.*)\}'
        for record in re.split(r",(?=\{(?:pack|level)=)",data):
            match = re.fullmatch(pattern,record)
            assert match,record[:100]
            level, mode, actions, samples = match.groups()
            actions, samples = array(actions), array(samples)
            commands = []
            for a in actions:
                kind = {"press":0,"drag":1,"release":2,"ghost":3,"cut":4,"pop":5}[a[1]]
                index, x, y = (0,a[2],a[3]) if box==11 else (a[2],0,0)
                commands.append(f"{a[0]} {kind} {index} {x} {y}\n")
            if not samples: continue
            result = subprocess.run([str(binary),str(box),level,str(samples[-1][0])],input="".join(commands),text=True,capture_output=True,check=True)
            actual = {row["tick"]:row for row in map(json.loads,result.stdout.splitlines())}
            worst = 0
            for sample in samples:
                tick, bodies = sample[:2]
                row = actual[tick]
                if bodies and len(bodies)!=len(row["bodies"]): failures.append((box,level,mode,tick,"bodycount"))
                for a,b in zip(bodies,row["bodies"]):
                    error = math.hypot(a[0]-b[0],a[1]-b[1]); worst = max(worst,error)
                    if error >= .05 or a[2:]!=b[2:len(a)]: failures.append((box,level,mode,tick,"body",error,a,b))
                if box==11:
                    for name,expected in zip(("grabs","discs","bubbles","pumps"),sample[2:]):
                        if len(expected)!=len(row[name]): failures.append((box,level,mode,tick,name,"count"))
                        for a,b in zip(expected,row[name]):
                            # Once C# has removed the candy, its terminal rope-tail
                            # disposal is no longer a live physics topology sample.
                            values = zip(a[:2],b[:2]) if name=="grabs" and not bodies else zip(a,b)
                            if max(abs(x-y) for x,y in values) > .02: failures.append((box,level,mode,tick,name,a,b))
                else:
                    if sample[2]!=row["ghosts"]: failures.append((box,level,mode,tick,"ghosts",sample[2],row["ghosts"]))
                    if sample[3:]!=row["counts"]: failures.append((box,level,mode,tick,"counts",sample[3:],row["counts"]))
            runs.append(dict(box=box,level=int(level),mode=mode,maximumError=worst))
report = dict(passed=not failures,sources=hashes,runs=runs,failures=failures)
(root/"build/contraptionstest.json").write_text(json.dumps(report,indent=2))
assert len(runs)==125,len(runs)
assert not failures,(len(failures),failures[:12])
print(f"PASS: {len(runs)} original C# DJ/Spooky input traces; maximum position error {max(r['maximumError'] for r in runs):.6f}")
