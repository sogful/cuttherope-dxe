"""Compare Tool/Buzz to independent original C# traces, never port-generated goldens."""
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
fixture = root.parent / 'roblox/tests/AdvancedGoldenData.luau'
traces = []
for line in fixture.read_text().splitlines():
    match = re.fullmatch(r'\{pack=(\d+),level=(\d+),action="(\w+)",samples=(.*)\},', line)
    if match:
        pack, level, action, samples = match.groups()
        traces.append((int(pack),int(level),action,json.loads(samples.replace('{','[').replace('}',']'))))
assert len(traces) >= 50
binary = root / 'build/advancedtest.exe'
subprocess.run([shutil.which('g++'), '-std=c++17', '-O2', '-Wall', '-Wextra', '-Werror', '-msse2', '-mfpmath=sse', '-ffp-contract=off',
    '-I'+str(root/'include'), '-I'+str(root/'generated'),
    *(str(root/'source'/name) for name in ('simulation.cpp','mechanics.cpp','advanced.cpp')),
    str(root/'tests/advanced.cpp'), '-o',str(binary)],check=True)
subprocess.run([str(binary)],check=True)
results, failures = [], []
for pack,level,action,samples in traces:
    output = subprocess.check_output([str(binary),str(pack),str(level),str(int(action=='rotate')),str(samples[-1][0])],text=True)
    actual = {row['tick']:row for row in map(json.loads,output.splitlines())}
    worst = 0
    for tick,bodies,ropes,spikes in samples:
        row = actual[tick]
        if bodies:
            if len(bodies)!=len(row['bodies']): failures.append((pack,level,action,tick,'bodycount'))
            for a,b in zip(bodies,row['bodies']):
                error = math.hypot(a[0]-b[0],a[1]-b[1]); worst = max(worst,error)
                if error >= .05 or a[2]!=b[2]: failures.append((pack,level,action,tick,'body',error,a,b))
        for a,b in zip(ropes,row['ropes']):
            if math.hypot(a[0]-b[0],a[1]-b[1]) > .02 or (b[2]>=0 and a[2]!=b[2]):
                failures.append((pack,level,action,tick,'rope',a,b))
        for a,b in zip(spikes,row['spikes']):
            if max(abs(x-y) for x,y in zip(a,b)) > .02: failures.append((pack,level,action,tick,'spike',a,b))
    results.append(dict(pack=pack,level=level,action=action,maximumError=worst))
report = dict(passed=not failures,sourceSha256=hashlib.sha256(fixture.read_bytes()).hexdigest(),runs=results,failures=failures)
(root/'build/advancedtest.json').write_text(json.dumps(report,indent=2))
assert not failures,(len(failures),failures[:10])
print(f"PASS: {len(traces)} C# Tool/Buzz trajectories, linked rotation, bee paths and rope topology; max error {max(r['maximumError'] for r in results):.6f}")
