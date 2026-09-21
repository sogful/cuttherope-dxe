"""Cheese/Pillow traces exported from the original C# scene, not DS-generated goldens."""
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
binary = root / "build/nocturnaltest.exe"
subprocess.run([shutil.which("g++"), "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-msse2", "-mfpmath=sse", "-ffp-contract=off",
    "-I"+str(root/"include"), "-I"+str(root/"generated"),
    *(str(root/"source"/name) for name in ("simulation.cpp","mechanics.cpp","advanced.cpp","contraptions.cpp","devices.cpp","nocturnal.cpp","conveyors.cpp","levelstore.cpp")),
    str(root/"tests/nocturnal.cpp"), "-o",str(binary)],check=True)
subprocess.run([str(binary)],check=True)
runs, hashes, failures, cosmetic = [], {}, [], []
array = lambda s: json.loads(s.replace("{","[").replace("}","]"))
for group, box in (("Cheese",15),("Pillow",16)):
    for fixture in sorted((root.parent/"roblox/tests").glob(group+"GoldenData[0-9]*.luau")):
        hashes[fixture.name] = hashlib.sha256(fixture.read_bytes()).hexdigest()
        data = fixture.read_text().split("return ",1)[1].strip()
        if not data.startswith("{level="): data = data[1:-1]
        for record in re.split(r",(?=\{level=)",data):
            match = re.fullmatch(r'\{level=(\d+),mode=(\d+),actions=(.*?),samples=(.*)\}',record)
            assert match,record[:160]
            level,mode,actions,samples = match.groups()
            actions,samples = array(actions),array(samples)
            commands = "".join(f"{a[0]} {dict(mouse=0,cut=1,pop=2)[a[1]]} {a[2]} {int(a[3]) if len(a)>3 else 1}\n" for a in actions)
            result = subprocess.run([str(binary),str(box),level,str(samples[-1][0])],input=commands,text=True,capture_output=True,check=True)
            actual = {r["tick"]:r for r in map(json.loads,result.stdout.splitlines())}
            worst = 0
            for r in actual.values():
                if not r["input"]: failures.append((box,level,mode,r["tick"],"input"))
            for sample in samples:
                tick,bodies = sample[:2]; row = actual[tick]
                if len(bodies)!=len(row["bodies"]): failures.append((box,level,mode,tick,"body count",len(bodies),len(row["bodies"])))
                for i,(a,b) in enumerate(zip(bodies,row["bodies"])):
                    error = math.hypot(a[0]-b[0],a[1]-b[1]); worst = max(worst,error)
                    if error>=.05: failures.append((box,level,mode,tick,"position",i,error,a,b))
                    if tick and math.hypot(a[2]-b[2],a[3]-b[3])>=.05: failures.append((box,level,mode,tick,"previous",i,a,b))
                    if a[4:]!=b[4:len(a)]: failures.append((box,level,mode,tick,"body flags",i,a,b))
                if box==15:
                    if sample[2]!=row["active"]: failures.append((box,level,mode,tick,"owner",sample[2],row["active"]))
                    for a,b in zip(sample[3],row["mice"]):
                        if a[:4]!=b[:4] or abs(a[4]-b[4])>=.0001: failures.append((box,level,mode,tick,"mouse",a,b))
                else:
                    for i,(a,b) in enumerate(zip(sample[2],row["lit"])):
                        if a==b: continue
                        # C# fixtures did not seed Star.CreateAnimations' +/-3
                        # pixel random bob or export its retirement. Validate
                        # every unretired illumination sample outside that band.
                        if row["collected"][i] or abs(row["lightedge"][i])<=3.01:
                            cosmetic.append((int(level),int(mode),tick,i,"retired" if row["collected"][i] else "bob",row["lightedge"][i]))
                        else: failures.append((box,level,mode,tick,"light",i,a,b,row["lightedge"][i]))
            runs.append(dict(box=box,level=int(level),mode=int(mode),maximumError=worst))
report = dict(passed=not failures,sources=hashes,runs=runs,failures=failures,cosmeticLightingDifferences=cosmetic)
(root/"build/nocturnaltest.json").write_text(json.dumps(report,indent=2))
assert len(runs)==150,len(runs)
assert not failures,(len(failures),failures[:8])
print(f"PASS: {len(runs)} original C# Cheese/Pillow input traces; maximum position error {max(r['maximumError'] for r in runs):.6f}")
print(f"Lighting: {len(cosmetic)} randomized-bob or retired-star differences documented separately")
