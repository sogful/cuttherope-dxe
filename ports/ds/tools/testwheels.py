"""Compare Gift/Cosmic with the checked-in original C# scene trace export."""
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
fixture = root.parent / "roblox/tests/WheelGoldenData.luau"
traces = []
for line in fixture.read_text().splitlines():
    match = re.fullmatch(r'\{pack=(\d+),level=(\d+),action="(\w+)",actions=(.*),samples=(.*)\},', line)
    if not match:
        continue
    pack, level, action, actions, samples = match.groups()
    parse = lambda value: json.loads(value.replace("{", "[").replace("}", "]"))
    traces.append((int(pack), int(level), action, parse(actions), parse(samples)))
assert len(traces) == 56
binary = root / "build/wheeltest.exe"
subprocess.run([shutil.which("g++"), "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-msse2", "-mfpmath=sse", "-ffp-contract=off",
    "-I" + str(root / "include"), "-I" + str(root / "generated"),
    *(str(root / "source" / name) for name in ("simulation.cpp", "mechanics.cpp", "advanced.cpp", "contraptions.cpp", "devices.cpp","nocturnal.cpp","conveyors.cpp")),
    str(root / "tests/wheels.cpp"), "-o", str(binary)], check=True)
subprocess.run([str(binary)], check=True)
results, failures = [], []
for pack, level, action, actions, samples in traces:
    mode = {"idle": 0, "wheel": 1, "gravity": 2}[action]
    output = subprocess.check_output([str(binary), str(pack), str(level), str(mode), str(samples[-1][0])],
        input="\n".join(" ".join(map(str, item)) for item in actions), text=True)
    actual = {row["tick"]: row for row in map(json.loads, output.splitlines())}
    worst, checked = 0, 0
    for tick, bodies, ropes in samples:
        if not bodies:
            continue
        row = actual[tick]
        error = math.hypot(row["x"] - bodies[0][0], row["y"] - bodies[0][1])
        worst = max(worst, error)
        if error >= .05 or row["bubble"] != bodies[0][2]:
            failures.append((pack, level, action, tick, error, "body"))
        for i, rope in enumerate(ropes):
            if rope and (row["ropes"][i][0] != rope[0] or abs(row["ropes"][i][1] - rope[1]) > 1 or abs(row["ropes"][i][2] - rope[2]) > .001):
                failures.append((pack, level, action, tick, row["ropes"][i], rope))
        checked += 1
    results.append(dict(pack=pack, level=level, action=action, samples=checked, maximumError=worst))
report = dict(passed=not failures, sourceSha256=hashlib.sha256(fixture.read_bytes()).hexdigest(), runs=results, failures=failures)
(root / "build/wheeltest.json").write_text(json.dumps(report, indent=2))
assert not failures, (len(failures), failures[:10])
print(f"PASS: {len(traces)} C# Gift/Cosmic trajectories, wheel topology/rest lengths, gravity and bubble reversal; max error {max(row['maximumError'] for row in results):.6f}")
