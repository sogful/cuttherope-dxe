import xml.etree.ElementTree as xml
from levels import boxes

touchtext = {
    "TUTORIAL_LVL_1_1_01": "Swipe across or tap to cut the rope",
    "TUTORIAL_LVL_1_5_01": "Tap to pop the bubble",
    "TUTORIAL_LVL_2_1_01": "Tap the air cushion to blow the object",
    "TUTORIAL_LVL_3_1_01": "Some rope hooks can be moved with the stylus",
}


def build(menu):
    info = {"items": [], "spans": []}
    names = set()
    for box in range(1, boxes + 1):
        for level in range(1, 26):
            path = menu["content"] / "maps" / f"{box}_{level}.xml"
            menu["sources"].add(path)
            document = xml.parse(path).getroot()
            width = float(document.find("./layer[@name='settings']/map").get("width")) * 3
            design = document.find("./layer[@name='settings']/gameDesign")
            left = (2560 - width) / 2 + float(design.get("mapOffsetX", 0))
            top = float(design.get("mapOffsetY", 0))
            rows = []
            for code in menu["codes"]:
                strings = {**menu["locale"]("en")["TUTORIAL_TEXTS"], **menu["locale"](code).get("TUTORIAL_TEXTS", {})}
                nodes = [n for n in document.iter() if n.get("locale") == code]
                if not nodes:
                    nodes = [n for n in document.iter() if n.get("locale") == "en"]
                first = len(info["items"])
                for node in nodes:
                    if not node.tag.startswith("tutorial"):
                        continue
                    if node.tag == "tutorialText" and not node.get("text"):
                        continue  # DX's skipInvalid loader ignores these empty editor placeholders.
                    x, y = float(node.get("x")) * 3 + left, float(node.get("y")) * 3 + top
                    if node.tag == "tutorialText":
                        name = f"hint{box}x{level}x{code}x{len(info['items'])}"
                        wrap = float(node.get("width")) * 3
                        key = node.get("text")
                        value = touchtext.get(key, strings[key]) if code == "en" else strings[key]
                        image, origin, height = menu["textimage"](value.replace("*", "\n"), code, True, wrap, factor=1)
                        menu["add"](name, image, f"texthints{box}x{level}x{code}", origin)
                        x += wrap / 2
                        y += height / 2
                    else:
                        index = int(node.tag[-2:]) - 1
                        name = "hintsign" + str(index)
                        if name not in names:
                            menu["quad"](name, "tutorial_signs", index, factor=1, group="hintsign" + str(index))
                            names.add(name)
                    area = [float(v) for v in node.get("inArea", "0,0,0,0").split(",")]
                    if node.get("inArea"):
                        area = [area[0] * 3 + left, area[1] * 3 + top, area[2] * 3, area[3] * 3]
                    pathvalues = [float(v) for v in node.get("path", "0,0,0,0").rstrip(",").split(",")]
                    mover = bool(node.get("path")) and not any(node.get(key) is not None for key in ("ease","moveDelay","repeat"))
                    if mover:
                        assert len(pathvalues)==2, (path,node.attrib)
                        pathvalues = [v*3 for v in pathvalues]+[0,0]
                    assert len(pathvalues) == 4
                    info["items"].append([name, x, y, float(node.get("angle", 0)), float(node.get("fadeIn", 1)),
                        float(node.get("duration", 5)), float(node.get("fadeOut", .5)), int(node.get("repeat", 1)),
                        -1 if mover else float(node.get("moveDelay", 0)), int(float(node.get("moveSpeed", 100))*3.3) if mover else float(node.get("moveSpeed", 0)) if node.get("path") else 0,
                        {"bubbled":1,"lanternCatch":2,"steamBurst":3,"mouseGrab":4}.get(node.get("showOn"),0), *area, *pathvalues])
                assert len(info["items"]) - first <= 32, (path, code, "Tutorial runtime capacity")
                rows.append([first, len(info["items"]) - first])
            info["spans"].append(rows)
    return info


def header(info, ids):
    lines = ['struct tutorial { int sprite; float x,y,angle,fadein,hold,fadeout,repeat,delay,speed,trigger; float left,top,width,height,firstx,firsty,lastx,lasty; };',
             'inline constexpr tutorial tutorials[] = {']
    lines += ['{' + str(ids[row[0]]) + ',' + ','.join(str(float(v)) + 'f' for v in row[1:]) + '},' for row in info['items']]
    lines += ['};', f'inline constexpr int tutorialspans[{boxes * 25}][12][2] = {{']
    lines += ['{' + ','.join('{' + ','.join(map(str, span)) + '}' for span in row) + '},' for row in info['spans']]
    return lines + ['};']


def refresh():
    """Refresh event metadata without re-encoding unchanged text/texture pages."""
    import json
    from assets import content, output
    path = output / "menumanifest.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    info = manifest["gameui"]["tutorials"]
    ids = {item["name"]:i for i,item in enumerate(manifest["sprites"])}
    old = "\n".join(header(info,ids))
    for level,spans in enumerate(info["spans"]):
        document = xml.parse(content / "maps" / f"{level//25+1}_{level%25+1}.xml")
        for code,(first,count) in zip(manifest["locales"],spans):
            nodes = [n for n in document.iter() if n.get("locale")==code]
            if not nodes: nodes = [n for n in document.iter() if n.get("locale")=="en"]
            nodes = [n for n in nodes if n.tag.startswith("tutorial") and (n.tag!="tutorialText" or n.get("text"))]
            assert len(nodes)==count
            for i,node in enumerate(nodes): info["items"][first+i][10] = {"bubbled":1,"lanternCatch":2,"steamBurst":3,"mouseGrab":4}.get(node.get("showOn"),0)
    target = output / "menuassets.hpp"
    source = target.read_text(encoding="utf-8")
    assert old in source
    target.write_text(source.replace(old,"\n".join(header(info,ids))),encoding="utf-8")
    path.write_text(json.dumps(manifest,indent=2,ensure_ascii=False),encoding="utf-8")


if __name__ == "__main__":
    refresh()
