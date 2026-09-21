"""Compare optimized and reference constraint traversal with identical float operations."""

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from levels import boxes

root = Path(__file__).resolve().parents[1]
compiler = shutil.which("g++")
if not compiler:
    raise SystemExit("A native g++ compiler is required.")
results = []
numeric = root / "build/numerictest.exe"
subprocess.run([compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-msse2", "-mfpmath=sse",
                "-ffp-contract=off", "-I" + str(root / "include"), str(root / "tests/numeric.cpp"), "-o", str(numeric)], check=True)
subprocess.run([str(numeric)], check=True)
for reference in (True, False):
    target = root / "build" / ("solver-reference.exe" if reference else "solver-optimized.exe")
    subprocess.run([
        compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-msse2", "-mfpmath=sse",
        "-ffp-contract=off", *(["-DDS_REFERENCE_PHYSICS"] if reference else []),
        "-I" + str(root / "include"), "-I" + str(root / "generated"),
        *(str(root / "source" / file) for file in ("simulation.cpp", "mechanics.cpp", "advanced.cpp", "contraptions.cpp", "devices.cpp")),
        str(root / "tests/solver.cpp"), "-o", str(target),
    ], check=True)
    results.append(subprocess.check_output([str(target)]).splitlines())
assert len(results[0]) == len(results[1]) == boxes * 25 * 1200
differences = [index for index, pair in enumerate(zip(*results)) if pair[0] != pair[1]]
assert not differences, ("Solver diverged", differences[:10])
report = {"maps": boxes * 25, "frames": len(results[0]), "divergentFrames": len(differences),
          "hash": hashlib.sha256(b"\n".join(results[0])).hexdigest()}
(root / "build/solvercomparison.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(f"PASS: optimized/reference float-state hashes match over all {boxes * 25} maps and {len(results[0]):,} frames")
