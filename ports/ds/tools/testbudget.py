import shutil
import subprocess
import re
import hashlib
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
binary = root / "build/renderbudget.exe"
palettes = root / "build/renderpalettes.cpp"
names = re.findall(
    r"extern const unsigned char (menupage\d+palette)\[\];",
    (root / "generated/menuassets.hpp").read_text(),
)
palettes.write_text(
    "\n".join('extern "C" const unsigned char ' + name + "[64] = {};" for name in names)
)
subprocess.run(
    [
        shutil.which("g++"),
        "-std=c++17",
        "-O1",
        "-Wall",
        "-Wextra",
        "-Werror",
        "-I" + str(root / "tests/renderstub"),
        "-I" + str(root / "include"),
        "-I" + str(root / "generated"),
        *[
            str(root / path)
            for path in (
                "tests/renderbudget.cpp",
                "source/simulation.cpp",
                "source/mechanics.cpp",
                "source/advanced.cpp",
                "source/contraptions.cpp",
                "source/devices.cpp",
                "source/nocturnal.cpp", "source/conveyors.cpp",
                "source/interface.cpp",
                "source/progress.cpp",
            )
        ],
        str(palettes),
        "-o",
        str(binary),
    ],
    check=True,
)
result = subprocess.run(
    [str(binary), str(root / "generated/nitro/menu.bin"), *(["contraptions"] if "--contraptions-only" in sys.argv else [])],
    capture_output=True,
    text=True,
)
print(result.stdout, end="")
print(result.stderr, end="")
(root / ("build/contraptionbudgetreport.json" if "--contraptions-only" in sys.argv else "build/budgetreport.json")).write_text(
    json.dumps(
        dict(
            passed=result.returncode == 0,
            output=result.stdout,
            manifestSha256=hashlib.sha256(
                (root / "generated/menumanifest.json").read_bytes()
            ).hexdigest(),
        ),
        indent=2,
    )
)
result.check_returncode()
