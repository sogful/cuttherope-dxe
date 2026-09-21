import json
from levels import boxes
import math
import uiscale
import xml.etree.ElementTree as xml

from PIL import Image, ImageDraw


def build(menu):
    quad, label, add = menu["quad"], menu["label"], menu["add"]
    fit, scale, content = menu["fit"], menu["scale"], menu["content"]
    assets = menu["assets"]
    info = {"labels": [], "digits": [], "resultdigits": [], "tutorials": [], "best": []}
    markers = json.loads((content / "images/menu_results.json").read_text())["frames"]
    points = [(f["spriteSourceSize"]["x"], f["spriteSourceSize"]["y"]) for f in markers[:13]]
    center = [(min(p[a] for p in points[:12]) + max(p[a] for p in points[:12])) / 2 for a in (0, 1)]
    resultfit = fit*uiscale.results
    info["anchors"] = [[round(128 + (p[0] - center[0]) * resultfit * scale), round(96 + (p[1] - center[1]) * resultfit * scale)] for p in points]
    for i in (13, 14, 15):
        quad("result" + str(i), "menu_results", i, factor=resultfit, group="resultart"+str(i))
    for i in range(17, 28):
        quad("stamp" + str(i), "menu_results", i, factor=resultfit, group="stamp" + str(i))
    for i,name in ((2,"resultdown"),(3,"resultup")):
        quad(name,"menu_buttons",i,factor=resultfit,group="menu_buttonsresult")
    for i in range(27):
        quad("confetti" + str(i), "confetti_particles", i, restore=True, group="confetti" + str(i // 9))
    for i in range(2):
        quad("cover" + str(i), "bgr_01_cover", i, factor=1, group="cover" + str(i))
    quad("doorshade", "menu_results", 16, factor=1, pixels=(128, 56), group="doorshade")
    for i in (6, 7):
        quad("loading" + str(i), "menu_level_ui", i, factor=1, group="loading")
    plate, _ = assets.readframe("menu_pause", 0)
    plate = plate.resize(tuple(round(v * 1.25 * scale) for v in plate.size), Image.Resampling.LANCZOS)
    left = (plate.width - 256) // 2
    add("pauseplate", plate.crop((left, 0, left + 256, plate.height)), "pauseplate")
    for i in range(19):
        quad("hud" + str(i), "hud_ui", i, factor=fit*uiscale.hud, restore=False, group="hud_ui" + (str(i) if i>=12 else ""))
    for i in (0, 3):
        quad("tutorial" + str(i), "tutorial_signs", i, factor=1, group="tutorials")
    info["hudquads"] = [12, 14, 13, 12, 18, 12, 12, 12, 16, 15, 17, 17]
    info["stamps"] = [17, 20, 19, 18, 22, 23, 26, 21, 25, 24, 27, 27]
    info["keys"] = ["LEVEL_CLEARED1", "LEVEL_CLEARED2", "LEVEL_CLEARED3", "LEVEL_CLEARED4", "STAR_BONUS", "TIME", "FINAL_SCORE", "REPLAY", "NEXT", "MENU",
                    "CONTINUE", "SKIP_LEVEL", "LEVEL_SELECT", "MAIN_MENU"]
    for code in menu["codes"]:
        strings = {**menu["locale"]("en"), **menu["locale"](code)}
        for section in list(strings.values()):
            if isinstance(section, dict):
                strings.update(section)
        row = []
        for key in info["keys"]:
            name = "game" + code + key
            small = key in ("STAR_BONUS", "TIME", "FINAL_SCORE")
            result = key in info["keys"][:10]
            label(name, strings[key], code, small, factor=resultfit if result else fit, group="textresult"+code+key if result else "textpause"+code)
            row.append(name)
        info["labels"].append(row)
        digits = []
        for i, char in enumerate("0123456789:"):
            name = "digit" + code + str(i)
            image, origin, _ = menu["textimage"](char, code, True)
            face, _ = menu["font"](code, True)
            add(name, image, "textdigits" + code, origin)
            digits.append((name, face.getlength(char) * fit * scale))
        info["digits"].append(digits)
        digits = []
        for i,char in enumerate("0123456789:"):
            name="resultdigit"+code+str(i)
            image,origin,_=menu["textimage"](char,code,True,factor=resultfit)
            add(name,image,"textresultdigits"+code,origin)
            digits.append((name,face.getlength(char)*resultfit*scale))
        info["resultdigits"].append(digits)
        name = "bestlabel" + code
        value = strings["BEST_SCORE"] + ": "
        label(name, value, code, True, group="textpause" + code)
        face, _ = menu["font"](code, True)
        info["best"].append((name, sum(face.getlength(c) for c in value) * fit * scale))
        for level in range(boxes * 25):
            label("levelname" + str(level) + code, f"{level // 25 + 1} - {level % 25 + 1}", code, factor=fit*uiscale.hud, group="textlevel" + code + str(level // 10))
        label("levelword" + code, strings["LEVEL"], code, factor=fit * .7 * uiscale.hud, group="texthud" + code)
    label("failuretitle", "TRY AGAIN!", "en", group="textfailure")
    label("failurehint", "Om Nom is still hungry!", "en", group="textfailure")
    face, height = menu["font"]("en")
    info["score"] = []
    for i in range(10):
        width = face.getlength(str(i))
        canvas = Image.new("RGBA", (math.ceil(width) + 20, 125))
        ImageDraw.Draw(canvas).text((10, 15 + face.getmetrics()[0]), str(i), font=face, anchor="ls", fill="black")
        image = canvas.resize((round(canvas.width * resultfit * scale), round(canvas.height * resultfit * scale)), Image.Resampling.LANCZOS)
        name = "scoredigit" + str(i)
        add(name, image, "textscoredigits", ((10 + width / 2) * resultfit * scale, 62.5 * resultfit * scale))
        info["score"].append((name, width * resultfit * scale))
    info["hud"] = []
    info["pause"] = [menu["position"](1280, (1440 - 897) / 2 + 88 + i * 181) for i in range(4)]
    info["pause"] += [menu["position"](1280 + sign * 351 / 2, (1440 - 897) / 2 + 724 + 173 / 2) for sign in (-1, 1)]
    frames = json.loads((content / "images/hud_ui.json").read_text())["frames"]
    for q in info["hudquads"]:
        pw, ph = (frames[q]["spriteSourceSize"][key] for key in ("w", "h"))
        rw, rh = (frames[0]["spriteSourceSize"][key] for key in ("w", "h"))
        info["hud"].append([round(256 - (8 + pw / 2) * fit * scale * uiscale.hud), round((8 + ph / 2) * fit * scale * uiscale.hud),
                            round(256 - (pw + 16 + rw / 2) * fit * scale * uiscale.hud), round((8 + rh / 2) * fit * scale * uiscale.hud)])
    import tutorials
    info["tutorials"] = tutorials.build(menu)
    return info


def header(info, ids):
    lines = ["inline constexpr int resultanchors[13][2] = {" + ",".join("{" + ",".join(map(str, p)) + "}" for p in info["anchors"]) + "};"]
    lines += ["enum gamekey {" + ",".join("game" + key for key in info["keys"]) + "};"]
    lines += ["inline constexpr int gamelabels[12][14] = {" + ",".join("{" + ",".join(str(ids[n]) for n in row) + "}" for row in info["labels"]) + "};"]
    lines += ["struct digit { int sprite; float advance; };", "inline constexpr digit digits[12][11] = {"]
    lines += ["{" + ",".join("{" + str(ids[n]) + f",{width:.6f}f" + "}" for n, width in row) + "}," for row in info["digits"]]
    lines += ["};", "inline constexpr digit scoredigits[10] = {" + ",".join("{" + str(ids[n]) + f",{width:.6f}f" + "}" for n, width in info["score"]) + "};"]
    lines += ["inline constexpr digit resultdigits[12][11] = {"]
    lines += ["{" + ",".join("{"+str(ids[n])+f",{width:.6f}f"+"}" for n,width in row)+"}," for row in info["resultdigits"]]
    lines += ["};"]
    lines += ["inline constexpr digit bestlabels[12] = {" + ",".join("{" + str(ids[n]) + f",{width:.6f}f" + "}" for n, width in info["best"]) + "};"]
    for key in ("hudquads", "stamps"):
        lines += ["inline constexpr int " + key + "[] = {" + ",".join(map(str, info[key])) + "};"]
    lines += ["inline constexpr int hudpositions[12][4] = {" + ",".join("{" + ",".join(map(str, p)) + "}" for p in info["hud"]) + "};"]
    lines += ["inline constexpr int pausepositions[6][2] = {" + ",".join("{" + ",".join(map(str, p)) + "}" for p in info["pause"]) + "};"]
    lines += [f"inline constexpr int levelnames[{boxes * 25}][12] = {{"]
    lines += ["{" + ",".join(str(ids["levelname" + str(level) + code]) for code in ("en","ru","de","fr","es","it","nl","pt_br","ko","ja","zh","zh_tw")) + "}," for level in range(boxes * 25)]
    lines += ["};"]
    lines += ["inline constexpr int levelwords[] = {" + ",".join(str(ids["levelword" + code]) for code in ("en","ru","de","fr","es","it","nl","pt_br","ko","ja","zh","zh_tw")) + "};"]
    import tutorials
    lines += tutorials.header(info["tutorials"], ids)
    return lines
