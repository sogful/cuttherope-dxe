import shutil
import subprocess
import uuid
from pathlib import Path

root=Path(__file__).resolve().parents[1]
binary=root/"build/gamelogtest.exe"
compiler=shutil.which("g++")
if not compiler: raise SystemExit("A native g++ compiler is required")
subprocess.run([compiler,"-std=c++17","-O2","-Wall","-Wextra","-Werror","-DDS_LOGGING",
    "-I"+str(root/"include"),str(root/"source/gamelog.cpp"),str(root/"tests/gamelog.cpp"),"-o",str(binary)],check=True)
directory=root/"build"/("gamelog-"+uuid.uuid4().hex)
directory.mkdir()
subprocess.run([str(binary),str(directory)],check=True)
