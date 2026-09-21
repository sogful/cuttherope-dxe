import shutil
import subprocess
from pathlib import Path

root=Path(__file__).resolve().parents[1]
binary=root/"build/bubbletest.exe"
subprocess.run([shutil.which("g++"),"-std=c++17","-O2","-Wall","-Wextra","-Werror",
    "-I"+str(root/"include"),"-I"+str(root/"generated"),
    *[str(root/"source"/(name+".cpp")) for name in
      ("simulation","mechanics","advanced","contraptions","devices","nocturnal","conveyors")],
    str(root/"tests/bubbles.cpp"),"-o",str(binary)],check=True)
subprocess.run([str(binary)],check=True)
