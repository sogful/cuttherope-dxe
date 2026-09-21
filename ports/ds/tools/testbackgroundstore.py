import json
import shutil
import subprocess
import sys
from pathlib import Path

import backgroundstore

root=Path(__file__).resolve().parents[1]
for name in ("world","upperbg"):
    data=backgroundstore.read(root/"generated",name)
    if len(sys.argv)>1:
        assert data==(Path(sys.argv[1])/(name+".bin")).read_bytes()
if len(sys.argv)>1:
    binary=root/"build/pagedtest.exe"
    subprocess.run([shutil.which("g++"),"-std=c++17","-O2","-Wall","-Wextra","-Werror",
        "-I"+str(root/"include"),"-I"+str(root/"generated"),str(root/"tests/paged.cpp"),"-o",str(binary)],check=True)
    subprocess.run([str(binary),str(root/"generated/nitro"),sys.argv[1]],check=True)
print("PASS: exact background reconstruction and packed/logical hashes")
