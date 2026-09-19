import hashlib
import json
import re
import shutil
import struct
import subprocess
from pathlib import Path

from PIL import Image, ImageFilter

root = Path(__file__).resolve().parents[1]
repo = root.parents[1]
generated = root / "generated"
manifest = json.loads((generated / "menumanifest.json").read_text(encoding="utf-8"))
assert manifest["viewport"] == [256, 192] and manifest["logical"] == [1920, 1440]
assert len(manifest["locales"]) == 12
for name, digest in manifest["sources"].items():
    assert hashlib.sha256((repo / "content" / name).read_bytes()).hexdigest() == digest, name
for name, digest in manifest["layoutSources"].items():
    assert hashlib.sha256((repo / name).read_bytes()).hexdigest() == digest, name
for name, digest in manifest["skinSources"].items():
    assert hashlib.sha256((repo / name).read_bytes()).hexdigest() == digest, name


def unpack(source):
    length = int.from_bytes(source[1:4], "little")
    assert source[0] == 0x10 and length <= 131072
    data = bytearray()
    cursor = 4
    while len(data) < length:
        flags = source[cursor]
        cursor += 1
        for bit in range(7, -1, -1):
            if len(data) == length:
                break
            if flags & (1 << bit):
                a, b = source[cursor:cursor + 2]
                cursor += 2
                distance = ((a & 15) << 8) + b + 1
                assert distance <= len(data)
                for _ in range((a >> 4) + 3):
                    data.append(data[-distance])
            else:
                data.append(source[cursor])
                cursor += 1
    assert len(data) == length and len(source) - cursor <= 3 and not any(source[cursor:])
    return data


compiler = shutil.which("g++")
assert compiler, "Native g++ is needed for the ROM's decoder checks"
binary = root / "build/packedtest.exe"
subprocess.run([compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-I" + str(root / "include"),
                str(root / "tests/packed.cpp"), "-o", str(binary)], check=True)
files = [generated / (page["name"] + ".lz") for page in manifest["pages"]]
native = []
for first in range(0, len(files), 64):
    native.extend(subprocess.check_output([str(binary), *map(str, files[first:first + 64])], text=True).splitlines())
assert len(native) == len(files)
atlases = []
for page, path, result in zip(manifest["pages"], files, native):
    data = unpack(path.read_bytes())
    expected = 2166136261
    for value in data:
        expected = ((expected ^ value) * 16777619) & 0xffffffff
    assert list(map(int, result.split())) == [len(data), expected], page["name"]
    assert len(data) == page["bytes"]
    atlas = Image.open(generated / (page["name"] + ".png")).convert("RGBA")
    atlases.append(atlas)
    if page["direct"]:
        actual = struct.unpack("<" + "H" * (len(data) // 2), data)
        for pixel, packed in zip(atlas.getdata(), actual):
            assert all(abs(((packed >> shift) & 31) - value * 31 / 255) <= 1 for shift, value in zip((0, 5, 10), pixel[:3]))
    else:
        bits = page["alphabits"]
        for pixel, packed in zip(atlas.getdata(), data):
            expected = pixel[3] * ((1 << bits) - 1) / 255
            if page["dither"]:
                assert abs((packed >> (8 - bits)) - expected) <= 1
            else:
                assert packed >> (8 - bits) == round(expected)

checked = 0
for item in manifest["sprites"]:
    source = item.get("source") or {}
    if "resource" not in source:
        continue
    path = repo / "content/images" / source["resource"]
    frame = json.loads(path.with_suffix(".json").read_text())["frames"][source["quad"]]
    sheet = Image.open(path.with_suffix(".png")).convert("RGBA")
    box = frame["frame"]
    crop = sheet.crop((box["x"], box["y"], box["x"] + box["w"], box["y"] + box["h"]))
    if frame.get("rotated"):
        crop = crop.transpose(Image.Transpose.ROTATE_90)
    if source["restore"]:
        image = Image.new("RGBA", (frame["sourceSize"]["w"], frame["sourceSize"]["h"]))
        image.paste(crop, (frame["spriteSourceSize"]["x"], frame["spriteSourceSize"]["y"]))
    else:
        image = crop
    size = source["pixels"] or [max(1, round(value * 192 / 1440 * source["factor"])) for value in image.size]
    image = image.resize(size, Image.Resampling.LANCZOS)
    if source.get("smooth"):
        image = image.filter(ImageFilter.GaussianBlur(.65))
    box = image.getbbox() or (0, 0, 1, 1)
    assert item["canvas"] == list(size) and item["trim"] == list(box)
    assert item["ox"] == round(box[0] - image.width / 2) and item["oy"] == round(box[1] - image.height / 2)
    x, y, w, h = (item[key] for key in ("x", "y", "w", "h"))
    actual = atlases[item["page"]].crop((x, y, x + w, y + h))
    assert actual.tobytes() == image.crop(box).tobytes(), item["name"]
    checked += 1

controls = manifest["controls"]
baselines = repo / "src/CutTheRopeDX.Tests/Baselines"
cases = [("MainMenu", "home", 8, ["packs", "options"], manifest["mainfit"]),
         ("Options", "options", 6, ["languages", "resetmenu", "credits"], manifest["fit"]),
         ("LanguageSelect", "languages", 8, ["language"] * 12, manifest["fit"]),
         ("CandySelect", "skins", 4, ["skintab"] * 4, 1),
         ("Reset", "resetmenu", 4, ["erase", "options"], manifest["fit"])]
positions = 0
for scene, view, indent, actions, scale in cases:
    lines = (baselines / ("Menu." + scene + ".FourThree.txt")).read_text()
    boxes = re.findall(r"^" + " " * indent + r"Button ([\d.-]+) ([\d.-]+) ([\d.-]+) ([\d.-]+)", lines, re.MULTILINE)
    targets = [item for item in controls if item["view"] == view and item["action"] in actions]
    assert len(boxes) == len(targets) == len(actions), (scene, boxes)
    for rect, item in zip(boxes, targets):
        x, y, width, height = map(float, rect)
        expected = [128 + (x + width / 2 - 960) * scale * 192 / 1440,
                    96 + (y + height / 2 - 720) * scale * 192 / 1440]
        assert abs(item["x"] - expected[0]) <= 1 and abs(item["y"] - expected[1]) <= 1, (scene, item, expected)
        positions += 1
header = (generated / "menuassets.hpp").read_text()
metrics = {name: float(value) for name, value in re.findall(r"inline constexpr float (skin\w+) = ([\d.]+)f;", header)}
grid = (baselines / "Menu.CandySelect.FourThree.txt").read_text()
boxes = re.findall(r"^            Button ([\d.-]+) ([\d.-]+) ([\d.-]+) ([\d.-]+)", grid, re.MULTILINE)
assert len(boxes) == 52
for index, rect in enumerate(boxes):
    x, y, w, h = map(float, rect)
    actual = [metrics["skinleft"] + (index % 4) * metrics["skinpitch"] + metrics["skinwidth"] / 2,
              metrics["skintop"] + (index // 4) * metrics["skinrow"] + (metrics["skinrow"] - 10 * manifest["fit"] * 192 / 1440) / 2]
    expected = [(x + w / 2) * 192 / 1440, (y + h / 2) * 192 / 1440]
    assert all(abs(a - b) < 1 for a, b in zip(actual, expected)), (index, actual, expected)
    positions += 1
report = dict(passed=True, sourceSprites=checked, sourceLayoutPositions=positions, packedPages=len(files),
              compressedBytes=sum(page["compressed"] for page in manifest["pages"]), locales=manifest["locales"])
(root / "build/menutest.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(f"PASS: {positions} C# 4:3 golden positions, {checked} source sprite registrations, {len(files)} ROM decoder round trips, 12 locale/font source sets")
