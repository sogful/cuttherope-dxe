"""Independent original C# Steam/Lantern traces, including dispatcher and input ordering."""
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
binary = root / "build/devicetest.exe"
subprocess.run([shutil.which("g++"), "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-msse2", "-mfpmath=sse", "-ffp-contract=off",
    "-I"+str(root/"include"), "-I"+str(root/"generated"),
    *(str(root/"source"/name) for name in ("simulation.cpp","mechanics.cpp","advanced.cpp","contraptions.cpp","devices.cpp","nocturnal.cpp","conveyors.cpp","levelstore.cpp")),
    str(root/"tests/devices.cpp"), "-o",str(binary)],check=True)
runs, hashes, failures = [], {}, []
array = lambda s: json.loads(s.replace("{","[").replace("}","]"))
for group, box in (("Steam",13),("Lantern",14)):
    for fixture in sorted((root.parent/"roblox/tests").glob(group+"GoldenData[0-9]*.luau")):
        hashes[fixture.name] = hashlib.sha256(fixture.read_bytes()).hexdigest()
        data = fixture.read_text().split("return ",1)[1].strip()
        if not data.startswith("{level="): data = data[1:-1]
        for record in re.split(r",(?=\{level=)",data):
            match = re.fullmatch(r'\{level=(\d+),mode=(\d+),actions=(.*?),samples=(.*)\}',record)
            assert match,record[:160]
            level,mode,actions,samples = match.groups()
            actions,samples = array(actions),array(samples)
            commands = "".join(f"{a[0]} {dict(valve=0,lantern=1,cut=2,pop=3)[a[1]]} {a[2]} {int(a[3])}\n" for a in actions)
            result = subprocess.run([str(binary),str(box),level,str(samples[-1][0])],input=commands,text=True,capture_output=True,check=True)
            actual = {r["tick"]:r for r in map(json.loads,result.stdout.splitlines())}
            worst = 0
            for r in actual.values():
                if not r["input"]: failures.append((box,level,mode,r["tick"],"input"))
            for sample in samples:
                tick,bodies = sample[:2]; row = actual[tick]
                if len(bodies)!=len(row["bodies"]): failures.append((box,level,mode,tick,"body count",len(bodies),len(row["bodies"])))
                for a,b in zip(bodies,row["bodies"]):
                    error = math.hypot(a[0]-b[0],a[1]-b[1]); worst = max(worst,error)
                    if error>=.05: failures.append((box,level,mode,tick,"position",error,a,b))
                    if box==13 and a[2]!=b[4] or box==14 and a[4:]!=b[4:]: failures.append((box,level,mode,tick,"body flags",a,b))
                    if box==14 and math.hypot(a[2]-b[2],a[3]-b[3])>=.05: failures.append((box,level,mode,tick,"previous",a,b))
                if box==13:
                    for a,b in zip(sample[2],row["tubes"]):
                        if a[0]!=b[0] or max(abs(x-y) for x,y in zip(a[1:],b[1:]))>=.001: failures.append((box,level,mode,tick,"tube",a,b))
                else:
                    if sample[2:4]!=[row["occupied"],row["shared"]]: failures.append((box,level,mode,tick,"ownership",sample[2:4],row["occupied"],row["shared"]))
                    for a,b in zip(sample[4],row["lanterns"]):
                        if a[3]!=b[3] or max(abs(x-y) for x,y in zip(a[:3],b[:3]))>=.01: failures.append((box,level,mode,tick,"lantern",a,b))
            runs.append(dict(box=box,level=int(level),mode=int(mode),maximumError=worst))
report = dict(passed=not failures,sources=hashes,runs=runs,failures=failures)
(root/"build/devicetest.json").write_text(json.dumps(report,indent=2))
assert len(runs)==150,len(runs)
assert not failures,(len(failures),failures[:8])
print(f"PASS: {len(runs)} original C# Steam/Lantern input traces; maximum position error {max(r['maximumError'] for r in runs):.6f}")
