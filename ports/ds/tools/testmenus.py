import hashlib
import json
import re
import shutil
import struct
import subprocess
import xml.etree.ElementTree as xml
from pathlib import Path
from levels import boxes

from PIL import Image, ImageFilter

root = Path(__file__).resolve().parents[1]
repo = root.parents[1]
generated = root / "generated"
manifest = json.loads((generated / "menumanifest.json").read_text(encoding="utf-8"))
assert manifest["viewport"] == [256, 192] and manifest["logical"] == [1920, 1440]
assert len(manifest["locales"]) == 12
tutorials = manifest["gameui"]["tutorials"]
for first, count in tutorials["spans"][400]:
    hands = [row for row in tutorials["items"][first:first + count] if row[0] == "hintsign9"]
    assert len(hands) == 1 and hands[0][8:10] == [-1, 330] and hands[0][15:19] == [-285, 147, 0, 0]
belts = [item for item in manifest["sprites"] if re.fullmatch(r"belt[0-6]", item["name"])]
assert len(belts) == 7 and [item["source"]["quad"] for item in belts] == list(range(7))
assert all(item["source"]["resource"] == "obj_conveyor" for item in belts)
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
streamed = (generated / "nitro/menu.bin").read_bytes()
for page, path, result in zip(manifest["pages"], files, native):
    palette = b"" if page["direct"] else (generated / (page["name"]+"palette.bin")).read_bytes()
    start=page["offset"]
    assert streamed[start:start+len(palette)] == palette
    assert streamed[start+len(palette):start+len(palette)+page["compressed"]] == path.read_bytes()
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
            if page["dither"] and page["dither"] != "low":
                assert abs((packed >> (8 - bits)) - expected) <= 1
            else:
                assert packed >> (8 - bits) == round(expected)

checked = 0
previews = 0
spriteids = {item["name"]:i for i,item in enumerate(manifest["sprites"])}
circles = [item for item in manifest['sprites'] if 'catchRadius' in (item.get('source') or {})]
expectedradii = {int(float(node.get("radius"))*3) for box in range(1,boxes+1) for level in range(1,26)
    for node in xml.parse(repo/f"content/maps/{box}_{level}.xml").iter()
    if node.tag in ("grab","ghost") and float(node.get("radius",-1)) >= 0}
assert {item["source"]["catchRadius"] for item in circles} == expectedradii
for item in circles:
    page = manifest['pages'][item['page']]
    assert page['alphabits'] == 5 and not page['dither']
    image = atlases[item['page']].crop((item['x'],item['y'],item['x']+item['w'],item['y']+item['h']))
    visible = [p for p in image.getdata() if p[3] > 32]
    assert len({p[3] for p in visible}) > 8, 'Catch radius lost its supersampled alpha fringe'
    assert all(p[2] > p[1] > p[0] for p in visible), 'DX catch radius must be blue, not black'
for stem, count, step in (("electro",5,1),("hat",5,1),("rail",5,1),("merge",5,1),("bouncer",10,1),("seat",boxes,1),("pump",4,2),("spike",4,2),("wheel",4,1),("gravity",3,1),("tool",8,1),("spider",13,1),("ghost",7,1),("ghosthook",2,1)):
    assert all(spriteids[stem+str(i)] == spriteids[stem+"0"] + i*step for i in range(count)), (stem,"Renderer animation IDs must match the atlas registration")
for item in manifest["sprites"]:
    source = item.get("source") or {}
    if item["name"].startswith("classicpreview"):
        assert all(v % 2 == 0 for v in item["canvas"]), "Classic preview needs an integer canvas pivot, not banker's rounding of half-pixel trim offsets"
        assert item["oy"] == item["trim"][1] - item["canvas"][1] // 2
    if source.get("preview"):
        image = Image.open(repo / source["baked"]).convert("RGBA").resize(source["pixels"], Image.Resampling.LANCZOS)
        assert all(v % 2 == 0 for v in image.size), "Preview canvas must keep an integer shared origin"
        box = image.getbbox() or (0, 0, 1, 1)
        assert item["trim"] == list(box) and item["ox"] == box[0] - image.width // 2 and item["oy"] == box[1] - image.height // 2
        x, y, w, h = (item[key] for key in ("x", "y", "w", "h"))
        assert atlases[item["page"]].crop((x, y, x + w, y + h)).tobytes() == image.crop(box).tobytes()
        previews += 1
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
    origin = (image.width // 2, image.height // 2) if source["restore"] else (image.width / 2, image.height / 2)
    if source.get("pivot"):
        origin = tuple(v * 192 / 1440 * source["factor"] for v in source["pivot"])
    assert item["ox"] == round(box[0] - origin[0]) and item["oy"] == round(box[1] - origin[1])
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
def generatedpoints(name):
    body = re.search(r"inline constexpr int " + name + r"\[[^;]+?= \{(.*?)\};", header, re.S).group(1)
    return [tuple(map(int, pair.split(","))) for pair in re.findall(r"\{([\d, -]+)\}", body)]

markers = json.loads((repo / "content/images/menu_results.json").read_text())["frames"]
markers = [(f["spriteSourceSize"]["x"], f["spriteSourceSize"]["y"]) for f in markers[:13]]
center = [(min(p[i] for p in markers[:12]) + max(p[i] for p in markers[:12])) / 2 for i in (0, 1)]
for actual, marker in zip(generatedpoints("resultanchors"), markers):
    expected = [128 + (marker[0] - center[0]) * manifest["fit"] * 192 / 1440, 96 + (marker[1] - center[1]) * manifest["fit"] * 192 / 1440]
    assert all(abs(a - b) <= .5 for a, b in zip(actual, expected))
for actual, quad in zip(generatedpoints("hudpositions"), (12,14,13,12,18,12,12,12,16,15,17,17)):
    frames = json.loads((repo / "content/images/hud_ui.json").read_text())["frames"]
    pause, restart = frames[quad]["spriteSourceSize"], frames[0]["spriteSourceSize"]
    scale = manifest["fit"] * 192 / 1440
    expected = [256 - (8 + pause["w"] / 2) * scale, (8 + pause["h"] / 2) * scale,
                256 - (pause["w"] + 16 + restart["w"] / 2) * scale, (8 + restart["h"] / 2) * scale]
    assert all(abs(a - b) <= .5 for a, b in zip(actual, expected))
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
              compressedBytes=sum(page["compressed"] for page in manifest["pages"]), locales=manifest["locales"], registeredPreviewFrames=previews,
              resultAnchors=13, localizedHudLayouts=12)
(root / "build/menutest.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(f"PASS: {positions} C# 4:3 golden positions, {checked} source sprite registrations, {len(files)} ROM decoder round trips, 12 locale/font source sets")
