import json
import math
from pathlib import Path
import struct

from PIL import Image

root = Path(__file__).resolve().parents[1]
content = root.parents[1] / "content/images"
generated = root / "generated"
manifest = json.loads((generated / "manifest.json").read_text())
assert manifest["viewport"] == [256, 192]
atlases = []
errors = {}
for page in manifest["atlases"]:
    name = page["name"]
    source = Image.open(generated / (name + ".png")).convert("RGBA")
    palette = struct.unpack("<32H", (generated / (name + "palette.bin")).read_bytes())
    data = (generated / (name + ".bin")).read_bytes()
    assert len(data) == source.width * source.height == page["bytes"]
    weighted, weight = 0, 0
    drift = [0, 0, 0]
    for expected, packed in zip(source.getdata(), data):
        alpha = expected[3]
        if page["dither"]:
            assert abs((packed >> 5) - alpha * 7 / 255) <= 1
        else:
            assert packed >> 5 == round(alpha * 7 / 255)
        if alpha < 128:
            continue
        actual = [((palette[packed & 31] >> shift) & 31) * 255 // 31 for shift in (0, 5, 10)]
        for channel in range(3):
            difference = actual[channel] - expected[channel]
            weighted += difference * difference * alpha
            drift[channel] += difference * alpha
        weight += alpha
    error = math.sqrt(weighted / (3 * weight))
    bias = [value / weight for value in drift]
    assert error < 18 and max(abs(value) for value in bias) < 8, (name, error, bias)
    errors[page["source"]] = {"rgbRms": error, "channelBias": bias}
    atlases.append(source)

sheets = {}
checked = 0
for record in manifest["sprites"]:
    if "source" not in record:
        continue
    resource = record["source"]
    if resource not in sheets:
        sheets[resource] = (Image.open(content / (resource + ".png")).convert("RGBA"),
                            json.loads((content / (resource + ".json")).read_text())["frames"])
    sheet, frames = sheets[resource]
    frame = frames[record["quad"]]
    box = frame["frame"]
    crop = sheet.crop((box["x"], box["y"], box["x"] + box["w"], box["y"] + box["h"]))
    if frame.get("rotated"):
        crop = crop.transpose(Image.Transpose.ROTATE_90)
    canvas, offset = frame["sourceSize"], frame["spriteSourceSize"]
    reference = Image.new("RGBA", (canvas["w"], canvas["h"])) if record["restore"] else Image.new("RGBA", crop.size)
    reference.paste(crop, (offset["x"], offset["y"]) if record["restore"] else (0, 0))
    ratio = (192 / 1440) * record["factor"]
    size = tuple(max(1, round(value * ratio)) for value in reference.size)
    reference = reference.resize(size, Image.Resampling.LANCZOS)
    rebuilt = Image.new("RGBA", size)
    x, y, width, height = (record[key] for key in ("x", "y", "w", "h"))
    crop = atlases[record["page"]].crop((x, y, x + width, y + height))
    rebuilt.paste(crop, (record["ox"] + size[0] // 2, record["oy"] + size[1] // 2))
    assert all(a == b or a[3] == b[3] == 0 for a, b in zip(rebuilt.getdata(), reference.getdata())), (resource, record["quad"], "animation anchor drift")
    checked += 1

assert len({record["page"] for record in manifest["sprites"]}) == len(manifest["atlases"])
assert manifest["texturebytes"] <= 384 * 1024
assert (generated / "logo.bin").stat().st_size == manifest["upperbytes"] == 48 * 1024
assert (generated / "logopalette.bin").stat().st_size == manifest["upperpalettebytes"] == 512
report = {"framesChecked": checked, "paletteErrors": errors, "textureBytes": manifest["texturebytes"], "passed": True}
(root / "build/visualtest.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(f"PASS: {checked} source-canvas animation anchors, {len(errors)} independent palettes, landscape viewport")
