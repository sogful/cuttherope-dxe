"""Link the same resident atlas bytes into native renderer tests."""
import re
import shutil
import subprocess


def build(root):
    compiler=shutil.which("g++")
    target=subprocess.check_output([compiler,"-dumpmachine"],text=True).strip()
    source=(root/"generated/assets.s").read_text()
    if target.startswith("i686-"):
        source=re.sub(r"(?m)^\.global (\w+)$",r".global _\1",source)
        source=re.sub(r"(?m)^(\w+):$",r"_\1:",source)
    (root/"build/hostassets.s").write_text(source)
    subprocess.run([compiler,"-c","build/hostassets.s","-o","build/hostassets.o"],cwd=root,check=True)
    return root/"build/hostassets.o"
