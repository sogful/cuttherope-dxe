import audioop
import hashlib
import json
import math
import struct
import wave
from functools import lru_cache
import xml.etree.ElementTree as xml
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps
import colors

root = Path(__file__).resolve().parents[1]
content = root.parents[1] / "content"
output = root / "generated"
scale = 192 / 1440
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


def sprite(name, resource, index, factor=1, restore=True):
    crop, frame = readframe(resource, index)
    bounds, canvas = frame["spriteSourceSize"], frame["sourceSize"]
    ratio = scale * factor
    restored = Image.new("RGBA", (canvas["w"], canvas["h"])) if restore else Image.new("RGBA", crop.size)
    restored.paste(crop, (bounds["x"], bounds["y"]) if restore else (0, 0))
    restored = restored.resize((max(1, round(restored.width * ratio)), max(1, round(restored.height * ratio))), Image.Resampling.LANCZOS)
    trim = restored.getbbox()
    records.append({"name": name, "image": restored.crop(trim),
                    "ox": trim[0] - restored.width // 2, "oy": trim[1] - restored.height // 2,
                    "canvas": list(restored.size), "trim": list(trim), "factor": factor, "restore": restore,
                    "source": resource, "quad": index})


def layout(items, width):
    x, y, row = 1, 1, 0
    positions = []
    for record in items:
        image = record["image"]
        if image.width + 2 > width:
            return None
        if x + image.width + 1 > width:
            x, y, row = 1, y + row + 2, 0
        positions.append((x, y))
        x += image.width + 2
        row = max(row, image.height)
    height = max(8, 1 << math.ceil(math.log2(y + row + 1)))
    return (width * height, width, height, positions) if height <= 1024 else None


def atlases():
    pages = []
    for resource in dict.fromkeys(record.get("source", "font") for record in records):
        items = [record for record in records if record.get("source", "font") == resource]
        _, width, height, positions = min(result for width in (32, 64, 128, 256) if (result := layout(items, width)))
        atlas = Image.new("RGBA", (width, height))
        page = len(pages)
        for record, (x, y) in zip(items, positions):
            image = record["image"]
            record.update(page=page, x=x, y=y, w=image.width, h=image.height)
            atlas.paste(image, (x, y))
        dither = resource != "font"
        lookup, palette = colors.palette(atlas, dither=dither)
        packed = bytearray(width * height)
        for record in items:
            data = colors.indexed(record["image"], lookup, dither, origin=(record["ox"], record["oy"]))
            for row in range(record["h"]):
                start = (record["y"] + row) * width + record["x"]
                packed[start:start + record["w"]] = data[row * record["w"]:(row + 1) * record["w"]]
        stem = "atlas" + str(page)
        atlas.save(output / (stem + ".png"))
        (output / (stem + ".bin")).write_bytes(packed)
        (output / (stem + "palette.bin")).write_bytes(palette)
        palette = struct.unpack("<32H", palette)
        preview = Image.new("RGBA", atlas.size)
        preview.putdata([tuple(((palette[pixel & 31] >> shift) & 31) * 255 // 31 for shift in (0, 5, 10)) + ((pixel >> 5) * 255 // 7,) for pixel in packed])
        preview.save(output / (stem + "preview.png"))
        pages.append({"name": stem, "source": resource, "width": width, "height": height, "bytes": len(packed), "dither": dither})
    return pages


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
        sprite("star" + str(index), "obj_star_idle", index, restore=index != 0)
    for index in range(3):
        sprite("candy" + str(index), "candies/obj_candy_01_new", index, .71)
    sprite("hookback", "obj_hook", 0)
    sprite("hookfront", "obj_hook", 1)
    sprite("support", "char_supports", 0)
    def ui(name, resource, index, width):
        crop, _ = readframe(resource, index)
        sprite(name, resource, index, width / crop.width / scale, restore=False)
    ui("restart", "hud_ui", 0, 23)
    ui("pause", "hud_ui", 12, 46)
    for index in range(11):
        sprite("hudstar" + str(index), "hud_ui", index + 1, 1.2)
    ui("button", "menu_buttons", 0, 112)
    ui("buttonpressed", "menu_buttons", 1, 112)
    ui("shortbutton", "menu_buttons", 3, 70)
    ui("shortpressed", "menu_buttons", 2, 70)
    ui("menutitle", "menu_pause", 0, 248)
    ui("audiobutton", "menu_options_packed", 0, 54)
    ui("audiopressed", "menu_options_packed", 1, 54)
    ui("soundicon", "menu_options_packed", 2, 21)
    ui("musicicon", "menu_options_packed", 3, 16)
    ui("disabledicon", "menu_options_packed", 4, 15)
    ui("resultstar", "menu_results", 13, 33)
    ui("resultempty", "menu_results", 14, 31)
    ui("separator", "menu_results", 15, 172)
    ui("levelcard", "menu_level_ui", 0, 58)
    fontpath = content / "fonts/gooddog_new-webfont.ttf"
    sources.add(fontpath)
    font = ImageFont.truetype(str(fontpath), 13)
    for character in range(32, 127):
        glyph = Image.new("RGBA", (10, 16))
        draw = ImageDraw.Draw(glyph)
        draw.text((0, -2), chr(character), font=font, fill="#fff2d9")
        records.append({"name": "glyph" + str(character), "image": glyph, "ox": 0, "oy": 0,
                        "advance": max(3, round(draw.textlength(chr(character), font=font)))})

    pages = atlases()

    (output / "nitro").mkdir(exist_ok=True)
    backgrounds = bytearray()
    for box in range(1, 7):
        path = images / f"backgrounds/bgr_{box:02}_p1.png"
        sources.add(path)
        background = Image.open(path).convert("RGB")
        width = round(background.height * 256 / 192)
        left = (background.width - width) // 2
        landscape = background.crop((left, 0, left + width, background.height)).resize((256, 192), Image.Resampling.LANCZOS)
        backdrop = Image.new("RGB", (256, 256))
        backdrop.paste(landscape, (0, 0))
        backgrounds.extend(colors.direct(backdrop))
        backdrop.save(output / ("background.png" if box == 1 else f"background{box}.png"))
    (output / "nitro/world.bin").write_bytes(backgrounds)

    logopath = root / "assets/logods.png"
    logo = ImageOps.contain(Image.open(logopath).convert("RGBA"), (256, 192), Image.Resampling.LANCZOS)
    upper = Image.new("RGB", (256, 256))
    upper.paste(logo, ((256 - logo.width) // 2, (192 - logo.height) // 2), logo)
    (output / "logo.bin").write_bytes(rgb15(upper))
    upper.crop((0, 0, 256, 192)).save(output / "logo.png")

    sfx = ["rope_bleak_1", "star_1", "star_2", "star_3", "monster_open", "monster_chewing", "win", "tap",
           "bubble", "bubble_break", "pump_1", "rope_get", "spider_activate", "spider_fall", "spider_win", "candy_break",
           "bouncer", "teleport", "candy_link", "electric"]
    audio = []
    for name in sfx + ["game_music", "menu_music"]:
        music = name.endswith("_music")
        path = content / ("sounds" if music else "sounds/sfx") / (name + ".wav")
        sources.add(path)
        with wave.open(str(path), "rb") as sound:
            data = sound.readframes(sound.getnframes())
            width = sound.getsampwidth()
            if sound.getnchannels() == 2:
                data = audioop.tomono(data, width, .5, .5)
            data, _ = audioop.ratecv(data, width, 1, sound.getframerate(), 11025 if music else 16000, None)
            data = audioop.lin2lin(data, width, 1 if music else 2)
        data += b"\0" * (-len(data) % 4)
        stem = name.replace("_", "")
        (output / (stem + ".bin")).write_bytes(data)
        audio.append((stem, len(data)))

    import levels
    levels.build(content, output, sources)

    blobs = [name for page in pages for name in (page["name"], page["name"] + "palette")] + ["logo"] + [name for name, _ in audio]
    header = ["#pragma once", "#include <cstdint>", 'extern "C" {']
    header += [f"extern const unsigned char {name}data[];" for name in blobs]
    header += ["}", "namespace art {", "struct sprite { int x, y, w, h, ox, oy, advance, page; };",
               "struct texture { int width, height; const unsigned char* pixels; const unsigned char* palette; int kind; };",
               "inline constexpr texture textures[] = {"]
    header += [f"{{{page['width']},{page['height']},{page['name']}data,{page['name']}palettedata,{1 if page['source'].startswith('char_animations') else 2 if page['source'].startswith('candies/') else 0 if page['source'].startswith(('obj_', 'char_supports')) else 3}}}," for page in pages]
    header += ["};", f"inline constexpr int texturecount = {len(pages)};", "enum id {"]
    header += [record["name"] + "," for record in records]
    header += ["spritecount };", "inline constexpr sprite sprites[] = {"]
    header += ["{" + ",".join(str(record.get(key, 0)) for key in ("x", "y", "w", "h", "ox", "oy", "advance", "page")) + "}," for record in records]
    header += ["};", "}"]
    header += [f"inline constexpr int {name}bytes = {size};" for name, size in audio]
    (output / "assets.hpp").write_text("\n".join(header) + "\n", encoding="utf-8")
    assembly = ['.section .rodata', '.balign 4']
    for name in blobs:
        assembly += [".balign 4", f".global {name}data", f"{name}data:", f'.incbin "generated/{name}.bin"']
    (output / "assets.s").write_text("\n".join(assembly) + "\n", encoding="utf-8")
    manifest = {"level": "1_1", "levelCount": 150, "viewport": [256, 192], "scale": scale, "atlases": pages,
                "texturebytes": sum(page["bytes"] for page in pages) + 131072,
                "upperbytes": 131072, "logo": {"source": "assets/logods.png", "sha256": hashlib.sha256(logopath.read_bytes()).hexdigest()},
                "audiobytes": sum(size for _, size in audio),
                "sources": {str(path.relative_to(content)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(sources)},
                "sprites": [{key: value for key, value in record.items() if key != "image"} for record in records]}
    assert manifest["texturebytes"] <= 384 * 1024, "Main-engine textures exceed VRAM A+B+D"
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Converted 150 original maps, {len(records)} base sprites, {manifest['texturebytes']} base texture bytes, {manifest['audiobytes']} audio bytes")
    import menus
    menus.main()


if __name__ == "__main__":
    main()
