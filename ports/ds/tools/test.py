import json
import math
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
build = root / "build"
build.mkdir(exist_ok=True)
compiler = shutil.which("g++")
if not compiler:
    raise SystemExit("A native g++ compiler is required for the host simulation checks.")
binary = build / "simulationtest.exe"
subprocess.run([compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-msse2", "-mfpmath=sse", "-ffp-contract=off",
                "-I" + str(root / "include"), "-I" + str(root / "generated"),
                str(root / "source/simulation.cpp"), str(root / "source/mechanics.cpp"), str(root / "source/advanced.cpp"), str(root / "source/contraptions.cpp"), str(root / "source/devices.cpp"), str(root / "source/nocturnal.cpp"), str(root / "source/conveyors.cpp"), str(root / "tests/simulation.cpp"), "-o", str(binary)], check=True)
result = json.loads(subprocess.check_output([str(binary)], text=True))
traces = json.loads((root.parent / "roblox/tests/desktop-trajectories.json").read_text())
reference = next(trace for trace in traces if trace["level"] == 1)["samples"]
assert len(reference) == len(result["samples"])
errors = []
for expected, actual in zip(reference, result["samples"]):
    assert expected["tick"] == actual["tick"]
    error = math.hypot(expected["x"] - actual["x"], expected["y"] - actual["y"])
    errors.append(error)
    assert error < .05, (expected, actual, error)
result["maximumDesktopError"] = max(errors)
(build / "simulationtest.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
print(f"PASS: {len(reference)} real DX reference samples; maximum error {max(errors):.6f} DX pixels")
print("PASS:", result["checks"])
binary = build / "leveltest.exe"
subprocess.run([compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-msse2", "-mfpmath=sse", "-ffp-contract=off",
                "-I" + str(root / "include"), "-I" + str(root / "generated"), str(root / "source/simulation.cpp"),
                str(root / "source/mechanics.cpp"), str(root / "source/advanced.cpp"), str(root / "source/contraptions.cpp"), str(root / "source/devices.cpp"), str(root / "source/nocturnal.cpp"), str(root / "source/conveyors.cpp"), str(root / "source/levelstore.cpp"), str(root / "tests/levels.cpp"), "-o", str(binary)], check=True)
result = json.loads(subprocess.check_output([str(binary)], text=True))
for actual in result["traces"]:
    expected = next(trace for trace in traces if trace["level"] == actual["level"])
    for a, b in zip(actual["samples"], expected["samples"]):
        assert a["tick"] == b["tick"] and math.hypot(a["x"] - b["x"], a["y"] - b["y"]) < .05, (actual["level"], a, b)
(build / "leveltest.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
print(f"PASS: four DX trajectories, {result['maps']} XML maps, {result['frames']:,} finite-coordinate frames, original and advanced mechanics")
subprocess.run([sys.executable, str(root / "tools/testmovers.py")], check=True)
binary = build / "interfacetest.exe"
subprocess.run([compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                "-I" + str(root / "include"), "-I" + str(root / "generated"),
                str(root / "source/simulation.cpp"), str(root / "source/mechanics.cpp"), str(root / "source/advanced.cpp"), str(root / "source/contraptions.cpp"), str(root / "source/devices.cpp"), str(root / "source/nocturnal.cpp"), str(root / "source/conveyors.cpp"), str(root / "source/interface.cpp"), str(root / "source/progress.cpp"),
                str(root / "tests/interface.cpp"), "-o", str(binary)], check=True)
subprocess.run([str(binary)], check=True)
binary = build / "progresstest.exe"
subprocess.run([compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-I" + str(root / "include"),
                str(root / "source/progress.cpp"), str(root / "tests/progress.cpp"), "-o", str(binary)], check=True)
directory = build / ("savetest" + uuid.uuid4().hex)
directory.mkdir()
subprocess.run([str(binary), str(directory)], check=True)
subprocess.run([sys.executable, str(root / "tools/testwheels.py")], check=True)
subprocess.run([sys.executable, str(root / "tools/testbubbles.py")], check=True)
subprocess.run([sys.executable, str(root / "tools/testcurves.py")], check=True)
subprocess.run([sys.executable, str(root / "tools/testadvanced.py")], check=True)
subprocess.run([sys.executable, str(root / "tools/testcontraptions.py")], check=True)
subprocess.run([sys.executable, str(root / "tools/testdevices.py")], check=True)
subprocess.run([sys.executable, str(root / "tools/testnocturnal.py")], check=True)
subprocess.run([sys.executable, str(root / "tools/testconveyors.py")], check=True)
