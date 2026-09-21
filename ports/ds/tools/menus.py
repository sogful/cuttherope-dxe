"""DX MenuController, ContentFit, PackStripLayout and AboutView at 256x192."""
import hashlib
import json
import math
import struct
from collections import defaultdict, deque
from functools import lru_cache

from PIL import Image, ImageDraw, ImageFont, ImageOps, ImageFilter

import assets
import colors
from levels import boxes

root, content, output = assets.root, assets.content, assets.output
scale = 192 / 1440
fit = 1 + .55 * (((2560 / 1440) - (256 / 192)) / ((2560 / 1440) - .4)) ** 3
mainfit = min(fit, 672 / 665)
codes = ["en", "ru", "de", "fr", "es", "it", "nl", "pt_br", "ko", "ja", "zh", "zh_tw"]
names = ["English", "Russian", "German", "French", "Spanish", "Italian", "Dutch", "Portuguese", "Korean", "Japanese", "Chinese", "Tr. Chinese"]
records, pages, controls = [], [], []
sources = set()


def lz(data):
    result = bytearray(struct.pack("<I", (len(data) << 8) | 0x10))
    positions = defaultdict(lambda: deque(maxlen=32))
    cursor = 0
    while cursor < len(data):
        flag = len(result)
        result.append(0)
        for bit in range(7, -1, -1):
            if cursor >= len(data):
                break
            length, distance = 0, 0
            for start in reversed(positions[data[cursor:cursor + 3]]):
                if cursor - start > 4096:
                    break
                count = 0
                while count < 18 and cursor + count < len(data) and data[start + count] == data[cursor + count]:
                    count += 1
                if count > length:
                    length, distance = count, cursor - start
                if length == 18:
                    break
            used = length if length >= 3 else 1
            if length >= 3:
                result[flag] |= 1 << bit
                result.extend((((length - 3) << 4) | ((distance - 1) >> 8), (distance - 1) & 255))
            else:
                result.append(data[cursor])
            for position in range(cursor, cursor + used):
                positions[data[position:position + 3]].append(position)
            cursor += used
    result.extend(b"\0" * (-len(result) % 4))
    return bytes(result)


def add(name, image, group, origin=None, source=None):
    origin = origin or (image.width / 2, image.height / 2)
    box = image.getbbox() or (0, 0, 1, 1)
    records.append(dict(name=name, image=image.crop(box), group=group,
                        ox=round(box[0] - origin[0]), oy=round(box[1] - origin[1]),
                        canvas=list(image.size), origin=list(origin), trim=list(box), source=source))
    return len(records) - 1


def quad(name, resource, index, factor=fit, restore=False, group=None, pixels=None, smooth=False, pivot=None):
    crop, frame = assets.readframe(resource, index)
    sources.update((content / "images" / (resource + ".json"), content / "images" / (resource + ".png")))
    if restore:
        canvas = Image.new("RGBA", (frame["sourceSize"]["w"], frame["sourceSize"]["h"]))
        bounds = frame["spriteSourceSize"]
        canvas.paste(crop, (bounds["x"], bounds["y"]))
        crop = canvas
    size = pixels or (max(1, round(crop.width * scale * factor)), max(1, round(crop.height * scale * factor)))
    image = crop.resize(size, Image.Resampling.LANCZOS)
    if smooth:
        image = image.filter(ImageFilter.GaussianBlur(.65))
    origin = tuple(v * scale * factor for v in pivot) if pivot else (image.width // 2, image.height // 2) if restore else None
    return add(name, image, group or resource, origin,
               source={"resource": resource, "quad": index, "restore": restore, "factor": factor, "pixels": pixels, "smooth": smooth, "pivot": pivot})


@lru_cache(maxsize=None)
def locale(code):
    path = content / "locales" / (code + ".json")
    sources.add(path)
    return json.loads(path.read_text(encoding="utf-8"))


@lru_cache(maxsize=None)
def font(code, small=False):
    name, multiplier = {
        "ru": ("PlaypenSans-SemiBold.ttf", .9), "ko": ("Cafe24DongdongRegular.otf", .9),
        "ja": ("MPLUSRounded1c-Medium.ttf", .85), "zh": ("KNMaiyuan-Regular.ttf", .75),
        "zh_tw": ("KNMaiyuan-Regular.ttf", .75),
    }.get(code, ("gooddog_new-webfont.ttf", 1))
    path = content / "fonts" / name
    sources.add(path)
    probe = ImageFont.truetype(str(path), 1000)
    height = (72 if small else 100) * multiplier
    face = ImageFont.truetype(str(path), round(height * 1000 / sum(probe.getmetrics())))
    return face, height


def textimage(value, code, small=False, wrap=None, factor=fit, horizontal=1):
    face, height = font(code, small)
    def measure(line):
        return sum(face.getlength(char) for char in line)
    lines = []
    for paragraph in value.split("\n"):
        if not wrap:
            lines.append(paragraph)
            continue
        line = ""
        for word in paragraph.split(" "):
            candidate = (line + " " + word).lstrip()
            if line and measure(candidate) > wrap:
                lines.append(line)
                line = word
            else:
                line = candidate
            while measure(line) > wrap:
                end = max(1, next((i for i in range(1, len(line) + 1) if measure(line[:i]) > wrap), len(line)) - 1)
                lines.append(line[:end])
                line = line[end:]
        lines.append(line)
    top = 25 if small else -10
    width = wrap or max(1, max(measure(line) for line in lines))
    layoutheight = (height + 5) * len(lines) - 5 + top
    pad = 10
    canvas = Image.new("RGBA", (math.ceil(width) + pad * 2, math.ceil(layoutheight) + pad * 2))
    draw = ImageDraw.Draw(canvas)
    for i, line in enumerate(lines):
        x = pad + (width - measure(line)) / 2
        y = pad + top + face.getmetrics()[0] + int(height + 5) * i
        for char in line:
            if not small:
                draw.text((x + 2, y + 3), char, font=face, anchor="ls", fill="black", stroke_width=3, stroke_fill="black")
            draw.text((x, y), char, font=face, anchor="ls", fill="black" if small else "white",
                      stroke_width=0 if small else 3, stroke_fill="black")
            if not small:
                draw.text((x, y), char, font=face, anchor="ls", fill="white")
            x += face.getlength(char)
    sx, sy = scale * factor * horizontal, scale * factor
    image = canvas.resize((max(1, round(canvas.width * sx)), max(1, round(canvas.height * sy))), Image.Resampling.LANCZOS)
    return image, ((pad + width / 2) * sx, (pad + layoutheight / 2) * sy), layoutheight


def label(name, value, code, small=False, wrap=None, factor=fit, horizontal=1, group=None):
    image, origin, _ = textimage(value, code, small, wrap, factor, horizontal)
    return add(name, image, group or "text" + code, origin,
               {"locale": code, "text": value, "font": "small" if small else "big", "factor": factor, "wrap": wrap})


def background(name, fabric=False, cover=None, skin=False):
    canvas = Image.new("RGBA", (1920, 1440), "black")
    if cover:
        crop, _ = assets.readframe(cover, 0)
        canvas.alpha_composite(crop, (960 - crop.width, (1440 - crop.height) // 2))
        canvas.alpha_composite(crop.transpose(Image.Transpose.ROTATE_180), (960, (1440 - crop.height) // 2))
        rgb = canvas.convert("RGB").point(lambda channel: round(channel * .85))
        canvas = rgb.convert("RGBA")
        for index in (6, 7):
            crop, frame = assets.readframe("menu_level_ui", index)
            canvas.alpha_composite(crop, (frame["spriteSourceSize"]["x"] - 320, 80))
    elif skin:
        path = content / "images/backgrounds/skin_bg.png"
        sources.add(path)
        source = Image.open(path).convert("RGBA")
        canvas = ImageOps.fit(source, (1920, 1440), Image.Resampling.LANCZOS)
    else:
        for index in range(2 if fabric else 1):
            crop, _ = assets.readframe("menu_bgr", index)
            crop = crop.resize((round(crop.width * 1.25), round(crop.height * 1.25)), Image.Resampling.LANCZOS)
            canvas.alpha_composite(crop, ((1920 - crop.width) // 2, 1440 - crop.height))
    canvas = canvas.resize((256, 192), Image.Resampling.LANCZOS)
    full = Image.new("RGBA", (256, 256))
    full.paste(canvas, (0, 0))
    page = len(pages)
    pages.append({"name": name, "image": full, "direct": True, "bytes": 131072})
    records.append(dict(name=name, image=canvas, group="background", x=0, y=0, w=256, h=192, ox=-128, oy=-96, page=page))


def pack():
    for group in dict.fromkeys(record["group"] for record in records if "page" not in record):
        items = [record for record in records if record["group"] == group and "page" not in record]
        if group == "menu_bgr_shadow":
            width, height, positions = 256, 256, [(0, 0)]
        elif group == "pauseplate":
            width, height, positions = 256, max(8, 1 << math.ceil(math.log2(items[0]["image"].height))), [(0, 0)]
        elif len(items) == 1:
            width, height = (max(8, 1 << math.ceil(math.log2(size))) for size in items[0]["image"].size)
            positions = [(0, 0)]
        else:
            widths = (32,64,128,256,512) if group.startswith("rails") else (32,64,128,256)
            layouts = [result for width in widths if (result := assets.layout(items, width))]
            assert layouts, (group, [(r["name"], r["image"].size) for r in items])
            _, width, height, positions = min(layouts)
        assert width * height <= 131072, (group, width, height)
        canvas = Image.new("RGBA", (width, height))
        page = len(pages)
        for record, (x, y) in zip(items, positions):
            canvas.paste(record["image"], (x, y))
            record.update(x=x, y=y, w=record["image"].width, h=record["image"].height, page=page)
        pages.append(dict(name="menupage" + str(page), image=canvas, group=group, direct=False, bytes=width * height,
                          alphabits=5 if group in ("menu_bgr_shadow", "doorshade", "steampuffs") or group.startswith(("catch", "vinylring", "vinylcontour")) else 3,
                          dither=False if group in ("doorshade", "steampuffs") or group.startswith(("text", "packtext", "credits", "catch", "vinylring", "vinylcontour")) else
                          "low" if group.startswith(("menu_buttons", "menu_extra_buttons", "menu_options_packed", "skin_selection", "menu_level_ui", "hud_ui")) else True))
    members = defaultdict(list)
    for record in records:
        members[record["page"]].append(record)
    for number, page in enumerate(pages):
        if number % 128 == 0:
            print(f"Packing DS texture {number + 1}/{len(pages)}", flush=True)
        canvas, name = page["image"], page["name"]
        page.update(width=canvas.width, height=canvas.height)
        canvas.save(output / (name + ".png"))
        if page["direct"]:
            data = colors.direct(canvas)
        else:
            lookup, palette = colors.palette(canvas, 1 << (8 - page["alphabits"]), page["dither"])
            data = bytearray(canvas.width * canvas.height)
            for record in members[number]:
                encoded = colors.indexed(record["image"], lookup, page["dither"], page["alphabits"], (record["ox"], record["oy"]))
                for row in range(record["h"]):
                    start = (record["y"] + row) * canvas.width + record["x"]
                    data[start:start + record["w"]] = encoded[row * record["w"]:(row + 1) * record["w"]]
            (output / (name + "palette.bin")).write_bytes(palette)
        packed = lz(bytes(data))
        (output / (name + ".lz")).write_bytes(packed)
        page["compressed"] = len(packed)


def position(x, y, factor=fit):
    return [round(128 + (x - 1280) * scale * factor), round(96 + (y - 720) * scale * factor)]


def control(view, action, x, y, w, h, up, down, labelname="", argument=0, factor=fit, absolute=False):
    px, py = [x, y] if absolute else position(x, y, factor)
    controls.append(dict(view=view, action=action, x=px, y=py,
                         w=round(w if absolute else w * scale * factor), h=round(h if absolute else h * scale * factor),
                         up=up, down=down, label=labelname, argument=argument))


def main():
    output.mkdir(exist_ok=True)
    background("menuback")
    background("titleback", fabric=True)
    background("skinback", skin=True)
    quad("shadow", "menu_bgr_shadow", 0, pixels=(256, 256), smooth=True)
    quad("titlelogo", "menu_logo_new", 52, mainfit, group="title")
    for i in range(52):
        quad("titlecandy" + str(i), "menu_logo_new", i, mainfit, group="titlecandies" + str(i // 8))
    quad("titlehand", "candy_selection_fx", 1, mainfit, group="title")
    for i, name in enumerate(("longup", "longdown", "shortdown", "shortup")):
        quad(name, "menu_buttons", i)
    for i in range(11):
        quad("option" + str(i), "menu_options_packed", i)
    quad("backup", "menu_extra_buttons", 0)
    quad("backdown", "menu_extra_buttons", 1)
    for i in range(1, 10):
        quad("pack" + str(i), "menu_pack_ui", i, restore=i in (1, 2))
    for i in range(6):
        quad("level" + str(i), "menu_level_ui", i, restore=True)
    configs = json.loads((content / "ctroriginal_packs.json").read_text())
    sources.add(content / "ctroriginal_packs.json")
    for i, config in enumerate(configs):
        background("levelback" + str(i), cover=config["boxCover"][0])
    for i, config in enumerate(configs):
        resource = "menu_pack_selection" + ("2" if config["packSpritesheet"] == "2" else "")
        quad("box" + str(i), resource, config["packQuadIndex"], restore=True, group="box" + str(i))
    import skins
    skininfo = skins.build(globals())
    import gameui
    gameinfo = gameui.build(globals())
    import worldart
    rails = worldart.build(globals())
    import contraptionart
    contraptions = contraptionart.build(globals())
    keys = ["PLAY", "OPTIONS", "LANGUAGE", "RESET", "CREDITS", "YES", "NO", "RESET_TEXT", "DRAG_TO_CUT", "CLICK_TO_CUT",
            "CANDIES_BTN", "ROPE_SKINS_BTN", "OM_NOM_BTN", "TRACES_BTN", "unlockall", "unavailable"]
    keys += ["language" + str(i) for i in range(12)]
    keys += ["boxname" + str(i) for i in range(len(configs))]
    keys += ["hint" + str(i) for i in range(len(configs))]
    keys += ["total" + str(i) for i in range(boxes * 75 + 1)] + ["count" + str(i) for i in range(76)]
    keys += ["required" + str(i) for i in range(len(configs))] + ["number" + str(i) for i in range(1, 26)] + ["HARDEST_LABEL"]
    labelids, creditids, creditheights = [], [], []
    for code in codes:
        strings = {**locale("en"), **locale(code)}
        row = []
        for key in keys:
            small, wrap, factor, horizontal = False, None, fit, 1
            if key.startswith("language"):
                value = names[int(key[8:])]
            elif key.startswith("boxname"):
                i = int(key[7:])
                value = str(i + 1) + ". " + strings[configs[i]["packName"]]
                factor *= .75
                horizontal = .7 / .75 if code in ("en", "de") else 1
            elif key.startswith("hint"):
                value = strings["UNLOCK_HINT"].replace("%d", str(configs[int(key[4:])]["unlockStars"]))
                small, wrap, factor = True, 600, fit * .7
            elif key.startswith("required"):
                value, factor = str(configs[int(key[8:])]["unlockStars"]), fit * .7
            elif key.startswith("total"):
                value, factor = strings["TOTAL_STARS"].replace("%d", key[5:]), fit * .7
            elif key.startswith("count"):
                value, factor = key[5:] + "/75", fit * .7
            elif key.startswith("number"):
                value = key[6:]
            elif key in ("unlockall", "unavailable"):
                value = "Unlock all levels" if key == "unlockall" else "Not ported yet"
                small, factor = True, fit * .75
            else:
                value = strings[key]
                if key in ("DRAG_TO_CUT", "CLICK_TO_CUT"):
                    small, factor = True, fit * .75
                if key == "RESET_TEXT":
                    wrap = 1920 * .95 / fit
                if key == "HARDEST_LABEL":
                    factor *= .35
            group = ("packtext" if key.startswith(("boxname", "hint", "required", "total", "count")) else "text") + code
            if key.startswith(("total", "count")):
                group += key[:5] + str(int(key[5:]) // 16)
            row.append(label(code + key, value, code, small, wrap, factor, horizontal, group))
        labelids.append(row)
        width = round(1300 * scale)
        blocks = []
        top = Image.new("RGBA", (width, round(100 * fit * scale)))
        blocks.append(top)
        logopath = content / "images/CutTheRopeDXLogo.png"
        sources.add(logopath)
        logo = Image.open(logopath).convert("RGBA")
        blocks.append(logo.resize((round(logo.width * fit * scale), round(logo.height * fit * scale)), Image.Resampling.LANCZOS))
        creditkeys = ["ABOUT_FANWORK_MAIN", "ABOUT_FANWORK_PROJECT_WEBSITE", "ABOUT_FANWORK_PROJECT_NOTE", "ABOUT_FANWORK_CTRH_WEBSITE", "ABOUT_FANWORK_LEAD", "ABOUT_FANWORK_TEAM", "ABOUT_FANWORK_MEMBERS", "logo1", "ABOUT_TEXT", "logo2", "ABOUT_SPECIAL_THANKS"]
        for key in creditkeys:
            if key.startswith("logo"):
                crop, _ = assets.readframe("menu_logo", int(key[-1]))
                blocks.append(crop.resize((round(crop.width * fit * scale), round(crop.height * fit * scale)), Image.Resampling.LANCZOS))
            else:
                value = strings[key].replace("%versionNo%", "DS")
                image, origin, height = textimage(value, code, True, 1300 / fit)
                block = Image.new("RGBA", (width, max(1, round(height * fit * scale))))
                block.alpha_composite(image, (round(width / 2 - origin[0]), round(block.height / 2 - origin[1])))
                blocks.append(block)
        height = sum(image.height for image in blocks)
        canvas = Image.new("RGBA", (width, height))
        y = 0
        for image in blocks:
            canvas.alpha_composite(image, ((width - image.width) // 2, y))
            y += image.height
        canvas.save(output / ("credits-" + code + ".png"))
        ids = []
        for i, y in enumerate(range(0, height, 96)):
            image = canvas.crop((0, y, width, min(y + 96, height)))
            ids.append(add("credits" + code + str(i), image, "credits" + code + str(i), (0, 0)))
        creditids.append(ids)
        creditheights.append(height)
    control("home", "packs", 1280, 1086, 767, 206, "longup", "longdown", "PLAY", factor=mainfit)
    control("home", "options", 1280, 1267, 767, 206, "longup", "longdown", "OPTIONS", factor=mainfit)
    control("home", "skinmenu", 1423, 685.5, 281, 281, "", "", factor=mainfit)
    for action, x, icon in (("effects", 1103.5, 2), ("music", 1456.5, 3)):
        control("options", action, x, 220, 363, 174, "option0", "option1", argument=icon)
    for action, y, key in (("languages", 400, "LANGUAGE"), ("resetmenu", 581, "RESET"), ("credits", 762, "CREDITS")):
        control("options", action, 1280, y, 767, 206, "longup", "longdown", key)
    control("options", "clickcut", 1428.5, 1120, 239, 479, "", "")
    control("options", "unlock", 131, 185, 86, 11, "", "", absolute=True)
    for i in range(12):
        control("languages", "language", 868 + (i % 3) * 412, 449 + (i // 3) * 181, 451, 205, "shortup", "shortdown", "language" + str(i), i)
    control("resetmenu", "erase", 1280, 812, 767, 206, "longup", "longdown", "YES")
    control("resetmenu", "options", 1280, 1032, 767, 206, "longup", "longdown", "NO")
    control("packs", "previouspack", 25, 96, 20, 22, "pack6", "pack7", absolute=True)
    control("packs", "nextpack", 231, 96, 20, 22, "pack6", "pack7", absolute=True)
    control("packs", "openpack", 128, 96, 88, 88, "", "", absolute=True)
    for i, key in enumerate(("CANDIES_BTN", "ROPE_SKINS_BTN", "OM_NOM_BTN", "TRACES_BTN")):
        control("skins", "skintab", round(128 + (i - 1.5) * 364 * fit * scale), round(120 * fit * scale),
                round(340 * fit * scale), round(140 * fit * scale), "skin4", "skin5", key, i, absolute=True)
    for view in ("packs", "options", "languages", "credits", "resetmenu", "levels", "skins"):
        control(view, "back", 14, 178, 29, 29, "backup", "backdown", absolute=True)
    pack()
    ids = {record["name"]: i for i, record in enumerate(records)}
    header = ['#pragma once', '#include "interface.hpp"', '#include <cstdint>', 'extern "C" {']
    assembly = ['.section .rodata']
    nitro = output / "nitro"
    nitro.mkdir(exist_ok=True)
    blob = bytearray()
    for page in pages:
        page["offset"] = len(blob)
        blob.extend((output / (page["name"] + ".lz")).read_bytes())
        for suffix, extension in () if page["direct"] else (("palette", "palette.bin"),):
            symbol = page["name"] + suffix
            header.append(f"extern const unsigned char {symbol}[];")
            assembly.extend([".balign 4", f".global {symbol}", symbol + ":", f'.incbin "generated/{page["name"]}{extension}"'])
    (nitro / "menu.bin").write_bytes(blob)
    header += ['}', 'namespace menuart {', 'struct page { int width, height; bool direct; unsigned offset, packed; const unsigned char* palette; int alphabits; };',
               'struct sprite { std::int16_t x, y, w, h, ox, oy, page; };', 'static_assert(sizeof(sprite) == 14);', 'enum id {']
    assert all(-32768 <= record[key] <= 32767 for record in records for key in ("x", "y", "w", "h", "ox", "oy", "page"))
    header += [record["name"] + "," for record in records]
    header += ['spritecount };', 'inline constexpr sprite sprites[] = {']
    header += ['{' + ','.join(str(record[key]) for key in ("x", "y", "w", "h", "ox", "oy", "page")) + '},' for record in records]
    header += ['};', 'inline constexpr page pages[] = {']
    for page in pages:
        name = page["name"]
        header.append(f'{{{page["width"]},{page["height"]},{str(page["direct"]).lower()},{page["offset"]},{page["compressed"]},{"nullptr" if page["direct"] else name + "palette"},{page.get("alphabits", 0)}}},')
    header += ['};', f'inline constexpr int pagecount = {len(pages)};', 'enum label {']
    header += [key + ',' for key in keys]
    header += ['labelcount };', 'inline constexpr int labels[12][labelcount] = {']
    header += ['{' + ','.join(map(str, row)) + '},' for row in labelids]
    header += ['};', 'inline constexpr int creditheights[] = {' + ','.join(map(str, creditheights)) + '};']
    count = max(map(len, creditids))
    header += [f'inline constexpr int credits[12][{count}] = {{']
    header += ['{' + ','.join(map(str, row + [-1] * (count - len(row)))) + '},' for row in creditids]
    header += ['};', f'inline constexpr int boxcount = {len(configs)};', 'inline constexpr int thresholds[] = {' + ','.join(str(c["unlockStars"]) for c in configs) + '};', 'inline constexpr int boxes[] = {' + ','.join(str(ids["box" + str(i)]) for i in range(len(configs))) + '};',
               'struct control { ui::view view; ui::action action; int x, y, w, h, up, down, label, argument; };', 'inline constexpr control controls[] = {']
    for item in controls:
        fields = ["ui::view::" + item["view"], "ui::action::" + item["action"]]
        fields += [str(item[key]) for key in ("x", "y", "w", "h")]
        fields += [str(ids.get(item[key], -1)) for key in ("up", "down")]
        fields += [str(keys.index(item["label"]) if item["label"] else -1), str(item["argument"])]
        header.append('{' + ','.join(fields) + '},')
    header += ['};', f'inline constexpr int playableboxes = {boxes};', f'inline constexpr float fit = {fit:.8f}f;', f'inline constexpr float mainfit = {mainfit:.8f}f;']
    lockwidths = [[int(math.ceil(sum(font(code)[0].getlength(c) for c in str(config["unlockStars"]))) * .7) for config in configs] for code in codes]
    header += ['inline constexpr int lockwidths[12][17] = {'] + ['{' + ','.join(map(str,row)) + '},' for row in lockwidths] + ['};']
    header += skins.header(skininfo, ids, fit, scale)
    header += gameui.header(gameinfo, ids)
    header += worldart.header(rails, ids)
    header += contraptionart.header(contraptions, ids)
    header += ['inline constexpr int levelbacks[] = {' + ','.join(str(ids['levelback' + str(i)]) for i in range(17)) + '};', '}']
    (output / "menuassets.hpp").write_text('\n'.join(header) + '\n', encoding="utf-8")
    (output / "menuassets.s").write_text('\n'.join(assembly) + '\n', encoding="utf-8")
    sources.update(assets.sources)
    manifest = dict(viewport=[256, 192], logical=[1920, 1440], design=[2560, 1440], fit=fit, mainfit=mainfit,
                    controls=controls, locales=codes, creditheights=creditheights, lockwidths=lockwidths,
                    pages=[{key: value for key, value in page.items() if key != "image"} for page in pages],
                    sprites=[{key: value for key, value in record.items() if key != "image"} for record in records],
                    sources={str(path.relative_to(content)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(sources)})
    anchors = ["src/CutTheRopeDX.Core/GameMain/MenuController.cs", "src/CutTheRopeDX.Core/GameMain/MenuController.Layout.cs",
               "src/CutTheRopeDX.Core/GameMain/Resources.cs", "src/CutTheRopeDX.Core/GameMain/AboutView.cs",
               "src/CutTheRopeDX.Core/GameMain/PackStripLayout.cs", "src/CutTheRopeDX.Core/Framework/Platform/ContentFit.cs",
               "src/CutTheRopeDX.Core/Framework/Platform/FittedContentFit.cs", "src/CutTheRopeDX.Core/Framework/LanguageHelper.cs",
               "src/CutTheRopeDX.Rendering.Skia/SkiaFont.cs", "ports/roblox/src/ReplicatedStorage/PackScroller.luau",
               "ports/roblox/src/ReplicatedStorage/PackSelection.luau", "ports/roblox/src/StarterPlayerScripts/CutTheRopeClient.client.luau"]
    anchors += ["src/CutTheRopeDX.Core/GameMain/" + name + ".cs" for name in
                ("CandySelectionView", "SkinSelectionLayout", "SkinSelectionTabLayout", "OmNomSlotPreviewLayout", "RopeColorHelper")]
    anchors += ["src/CutTheRopeDX.Core/Framework/Core/RootController.cs", "ports/roblox/src/ReplicatedStorage/SessionState.luau"]
    manifest["layoutSources"] = {name: hashlib.sha256((root.parents[1] / name).read_bytes()).hexdigest() for name in anchors}
    manifest["skinSources"] = skininfo["sources"]
    manifest["gameui"] = gameinfo
    for name in ("BoxOpenClose", "GameController", "GameScene.Show", "GameScene", "CTRResourceMgr"):
        path = "src/CutTheRopeDX.Core/GameMain/" + name + ".cs"
        manifest["layoutSources"][path] = hashlib.sha256((root.parents[1] / path).read_bytes()).hexdigest()
    (output / "menumanifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"DX menus: {len(records)} sprites, {len(pages)} pageable textures, {sum(page['compressed'] for page in pages):,} compressed bytes")


if __name__ == "__main__":
    main()
