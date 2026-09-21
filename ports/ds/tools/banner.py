"""Convert the original SVG into the DS launcher's 32-pixel, 16-color icon."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

from PIL import Image

root = Path(__file__).resolve().parents[1]
title = "Cut the Rope DX;by yell0wsuit"


def update():
    source = root.parents[1]/"extras/images/icon.svg"
    target = root/"assets/icon.png"
    manifest = root/"assets/icon.json"
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    if target.exists() and manifest.exists():
        info = json.loads(manifest.read_text())
        if info["sourceSha256"] == digest and info["iconSha256"] == hashlib.sha256(target.read_bytes()).hexdigest():
            return target
    converter = shutil.which("inkscape") or str(Path(os.environ.get("ProgramFiles", "C:/Program Files"))/"Inkscape/bin/inkscape.com")
    if not Path(converter).exists():
        raise RuntimeError("Install Inkscape to regenerate the launcher icon from extras/images/icon.svg")
    preview = root/"build/icon-source.png"
    preview.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([converter, str(source), "--export-area-page", "--export-width=128", "--export-height=128",
                    "--export-type=png", "--export-filename="+str(preview)], check=True, timeout=120)
    image = Image.open(preview).convert("RGBA").resize((32,32), Image.Resampling.LANCZOS)
    colors = image.convert("RGB").quantize(colors=15, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    icon = Image.new("P", (32,32))
    palette = [0,0,0]+colors.getpalette()[:45]
    icon.putpalette(palette)
    icon.putdata([int(color)+1 if pixel[3]>=128 else 0 for color,pixel in zip(colors.getdata(),image.getdata())])
    icon.save(target, bits=4, transparency=0)
    manifest.write_text(json.dumps(dict(source="extras/images/icon.svg", sourceSha256=digest,
        iconSha256=hashlib.sha256(target.read_bytes()).hexdigest(), size=[32,32], colors=16),indent=2)+"\n")
    return target


if __name__ == "__main__":
    print(update())
