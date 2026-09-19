import audioop
import hashlib
import json
import math
import struct
import wave
from functools import lru_cache
import xml.etree.ElementTree as xml
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
content = root.parents[1] / "content"
output = root / "generated"
scale = 256 / 1440
images = content / "images"
records = []
sources = set()


@lru_cache(maxsize=None)
def sheet(resource):
    path = images / (resource + ".json")
    data = json.loads(path.read_text(encoding="utf-8"))
    source = images / (resource + ".png")
    sources.update((path, source))
    return Image.open(source).convert("RGBA"), data


def readframe(resource, index):
    image, data = sheet(resource)
    frame = data["frames"][index]
    box = frame["frame"]
    crop = image.crop((box["x"], box["y"], box["x"] + box["w"], box["y"] + box["h"]))
    if frame.get("rotated"):
        crop = crop.transpose(Image.Transpose.ROTATE_90)
    return crop, frame


def sprite(name, resource, index, factor=1):
    crop, frame = readframe(resource, index)
    bounds, canvas = frame["spriteSourceSize"], frame["sourceSize"]
    ratio = scale * factor
    crop = crop.resize((max(1, round(crop.width * ratio)), max(1, round(crop.height * ratio))), Image.Resampling.LANCZOS)
    records.append({"name": name, "image": crop,
                    "ox": round((bounds["x"] - canvas["w"] / 2) * ratio),
                    "oy": round((bounds["y"] - canvas["h"] / 2) * ratio),
                    "source": resource, "quad": index})


def rgb15(image):
    return b"".join(struct.pack("<H", 0x8000 | (r >> 3) | ((g >> 3) << 5) | ((b >> 3) << 10))
                    for r, g, b in image.convert("RGB").getdata())


def main():
    output.mkdir(exist_ok=True)
    for index in range(41):
        sprite("omnom" + str(index), "char_animations", index)
    for index in range(13):
        sprite("sad" + str(index), "char_animations3", index)
    for index in range(19):
        sprite("star" + str(index), "obj_star_idle", index)
    for index in range(3):
        sprite("candy" + str(index), "candies/obj_candy_01_new", index, .71)
    sprite("hookback", "obj_hook", 0)
    sprite("hookfront", "obj_hook", 1)
    sprite("support", "char_supports", 0)
    fontpath = content / "fonts/gooddog_new-webfont.ttf"
    sources.add(fontpath)
    font = ImageFont.truetype(str(fontpath), 13)
    for character in range(32, 127):
        glyph = Image.new("RGBA", (10, 16))
        draw = ImageDraw.Draw(glyph)
        draw.text((0, -2), chr(character), font=font, fill="#fff2d9")
        records.append({"name": "glyph" + str(character), "image": glyph, "ox": 0, "oy": 0,
                        "advance": max(3, round(draw.textlength(chr(character), font=font)))})

    atlas = Image.new("RGBA", (256, 1024))
    x, y, row = 1, 1, 0
    for record in records:
        image = record["image"]
        if x + image.width + 1 > atlas.width:
            x, y, row = 1, y + row + 2, 0
        if y + image.height + 1 > atlas.height:
            raise ValueError("Sprite atlas exceeded the DS texture limit")
        record.update(x=x, y=y, w=image.width, h=image.height)
        atlas.paste(image, (x, y))
        x += image.width + 2
        row = max(row, image.height)
    atlasheight = 1 << math.ceil(math.log2(y + row + 1))
    atlas = atlas.crop((0, 0, 256, atlasheight))
    atlas.save(output / "atlas.png")
    quantized = atlas.convert("RGB").quantize(colors=32, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    palette = quantized.getpalette()[:96]
    packed = bytes((int(round(alpha * 7 / 255)) << 5) | color
                   for alpha, color in zip(atlas.getchannel("A").getdata(), quantized.getdata()))
    (output / "atlas.bin").write_bytes(packed)
    (output / "palette.bin").write_bytes(b"".join(struct.pack("<H", (palette[i] >> 3) | ((palette[i + 1] >> 3) << 5) |
                                                                         ((palette[i + 2] >> 3) << 10)) for i in range(0, 96, 3)))
    preview = quantized.convert("RGBA")
    preview.putalpha(atlas.getchannel("A").point(lambda value: round(value * 7 / 255) * 255 // 7))
    preview.save(output / "atlaspreview.png")

    backgroundpath = images / "backgrounds/bgr_01_p1.png"
    sources.add(backgroundpath)
    background = Image.open(backgroundpath).convert("RGB")
    width = round(background.height * 192 / 256)
    left = (background.width - width) // 2
    portrait = background.crop((left, 0, left + width, background.height)).resize((192, 256), Image.Resampling.LANCZOS)
    backdrop = Image.new("RGB", (256, 256))
    backdrop.paste(portrait.transpose(Image.Transpose.ROTATE_90), (0, 0))
    (output / "background.bin").write_bytes(rgb15(backdrop))
    backdrop.save(output / "background.png")

    panel = Image.blend(portrait, Image.new("RGB", portrait.size, "#251a13"), .83)
    draw = ImageDraw.Draw(panel)
    titlefont = ImageFont.truetype(str(fontpath), 28)
    bodyfont = ImageFont.truetype(str(fontpath), 16)
    draw.text((17, 9), "Cut the Rope", font=titlefont, fill="#f7e8c3")
    draw.text((17, 40), "DX / Nintendo DS", font=bodyfont, fill="#b2ce5c")
    draw.line((16, 66, 175, 66), fill="#6b5037")
    draw.text((17, 77), "Cardboard Box 1-1", font=bodyfont, fill="#f7e8c3")
    draw.text((17, 138), "Swipe across the rope", font=bodyfont, fill="#f7e8c3")
    draw.text((17, 158), "Collect all three stars", font=bodyfont, fill="#f7e8c3")
    draw.text((17, 181), "A / touch: retry", font=bodyfont, fill="#b2ce5c")
    draw.text((17, 200), "START: pause", font=bodyfont, fill="#b2ce5c")
    draw.text((17, 232), "DS feasibility build", font=bodyfont, fill="#9c8c74")
    sub = Image.new("RGB", (256, 256))
    sub.paste(panel.transpose(Image.Transpose.ROTATE_90), (0, 0))
    (output / "panel.bin").write_bytes(rgb15(sub))
    panel.save(output / "panelpreview.png")

    mask = Image.new("L", (96 * 6, 9))
    maskdraw = ImageDraw.Draw(mask)
    smallfont = ImageFont.load_default()
    for index in range(96):
        maskdraw.text((index * 6, -2), chr(32 + index), font=smallfont, fill=255)
    (output / "font.bin").write_bytes(bytes(1 if pixel >= 96 else 0 for pixel in mask.getdata()))

    sfx = ["rope_bleak_1", "star_1", "star_2", "star_3", "monster_open", "monster_chewing", "win"]
    audio = []
    for name in sfx:
        path = content / "sounds/sfx" / (name + ".wav")
        sources.add(path)
        with wave.open(str(path), "rb") as sound:
            data = sound.readframes(sound.getnframes())
            width = sound.getsampwidth()
            if sound.getnchannels() == 2:
                data = audioop.tomono(data, width, .5, .5)
            data, _ = audioop.ratecv(data, width, 1, sound.getframerate(), 16000, None)
            data = audioop.lin2lin(data, width, 2)
        data += b"\0" * (-len(data) % 4)
        stem = name.replace("_", "")
        (output / (stem + ".bin")).write_bytes(data)
        audio.append((stem, len(data)))

    mapfile = content / "maps/1_1.xml"
    sources.add(mapfile)
    document = xml.parse(mapfile).getroot()
    settings = document.find("./layer[@name='settings']/map")
    objects = document.find("./layer[@name='Objects']")
    width, height = int(settings.get("width")) * 3, int(settings.get("height")) * 3
    offset = (2560 - width) / 2
    def point(node):
        return "{" + str(float(node.get("x")) * 3 + offset) + "f, " + str(float(node.get("y")) * 3) + "f}"
    hooks = list(objects.findall("grab"))
    assert len(hooks) <= 8
    stars = list(objects.findall("star"))
    assert len(stars) == 3
    speed = float(document.find("./layer[@name='settings']/gameDesign").get("ropePhysicsSpeed")) * 1.4
    leveltext = "#pragma once\n#include \"simulation.hpp\"\nnamespace dx {\ninline const level firstlevel = {\n"
    leveltext += point(objects.find("candy")) + ", " + point(objects.find("target")) + ",\n{{" + ", ".join(point(star) for star in stars) + "}},\n{{"
    leveltext += ", ".join("{" + point(hook) + ", " + str(float(hook.get("length")) * 3) + "f}" for hook in hooks)
    leveltext += f"}}}},\n{len(hooks)}, {speed}f, {float(offset)}f, {float(width)}f, {float(height)}f\n}};\n}}\n"
    (output / "level.hpp").write_text(leveltext, encoding="utf-8")

    header = ["#pragma once", "#include <cstdint>", "namespace art {", "struct sprite { int x, y, w, h, ox, oy, advance; };",
              f"inline constexpr int atlasheight = {atlasheight};", "enum id {"]
    header += [record["name"] + "," for record in records]
    header += ["spritecount };", "inline constexpr sprite sprites[] = {"]
    header += ["{" + ",".join(str(record.get(key, 0)) for key in ("x", "y", "w", "h", "ox", "oy", "advance")) + "}," for record in records]
    header += ["};", "}", 'extern "C" {']
    blobs = ["atlas", "palette", "background", "panel", "font"] + [name for name, _ in audio]
    header += [f"extern const unsigned char {name}data[];" for name in blobs]
    header += ["}"]
    header += [f"inline constexpr int {name}bytes = {size};" for name, size in audio]
    (output / "assets.hpp").write_text("\n".join(header) + "\n", encoding="utf-8")
    assembly = ['.section .rodata', '.balign 4']
    for name in blobs:
        assembly += [".balign 4", f".global {name}data", f"{name}data:", f'.incbin "generated/{name}.bin"']
    (output / "assets.s").write_text("\n".join(assembly) + "\n", encoding="utf-8")
    manifest = {"level": "1_1", "atlas": [256, atlasheight], "texturebytes": len(packed) + 131072,
                "audiobytes": sum(size for _, size in audio),
                "sources": {str(path.relative_to(content)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(sources)},
                "sprites": [{key: value for key, value in record.items() if key != "image"} for record in records]}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Converted original level 1-1, {len(records)} sprites, {manifest['texturebytes']} texture bytes, {manifest['audiobytes']} audio bytes")


if __name__ == "__main__":
    main()
