import json
from pathlib import Path
import shutil
import subprocess

import hostassets

root=Path(__file__).resolve().parents[1]
binary=root/"build/uppertest.exe"
subprocess.run([shutil.which("g++"),"-std=c++17","-O2","-Wall","-Wextra","-Werror",
    "-I"+str(root/"tests/renderstub"),"-I"+str(root/"include"),"-I"+str(root/"generated"),
    str(root/"tests/upper.cpp"),*[str(root/"source"/(name+".cpp")) for name in
    ("simulation","mechanics","advanced","contraptions","devices","nocturnal","conveyors","interface","progress")],
    str(hostassets.build(root)),"-o",str(binary)],check=True)
result=subprocess.run([str(binary),(root/"generated/nitro").as_posix()+"/"],capture_output=True,text=True)
print(result.stdout,end=""); print(result.stderr,end="")
(root/"build/uppertest.json").write_text(json.dumps(dict(passed=result.returncode==0,output=result.stdout),indent=2))
result.check_returncode()
