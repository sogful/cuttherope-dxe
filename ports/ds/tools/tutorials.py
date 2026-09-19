import xml.etree.ElementTree as xml


def build(menu):
    info = {"items": [], "spans": []}
    names = set()
    for box in range(1, 3):
        for level in range(1, 26):
            path = menu["content"] / "maps" / f"{box}_{level}.xml"
            menu["sources"].add(path)
            document = xml.parse(path).getroot()
            width = float(document.find("./layer[@name='settings']/map").get("width")) * 3
            left = (2560 - width) / 2
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
                    x, y = float(node.get("x")) * 3 + left, float(node.get("y")) * 3
                    if node.tag == "tutorialText":
                        name = f"hint{box}x{level}x{code}x{len(info['items'])}"
                        wrap = float(node.get("width")) * 3
                        image, origin, height = menu["textimage"](strings[node.get("text")].replace("*", "\n"), code, True, wrap, factor=1)
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
                        area = [area[0] * 3 + left, area[1] * 3, area[2] * 3, area[3] * 3]
                    pathvalues = [float(v) for v in node.get("path", "0,0,0,0").split(",")]
                    assert len(pathvalues) == 4
                    info["items"].append([name, x, y, float(node.get("angle", 0)), float(node.get("fadeIn", 1)),
                        float(node.get("duration", 5)), float(node.get("fadeOut", .5)), int(node.get("repeat", 1)),
                        float(node.get("moveDelay", 0)), float(node.get("moveSpeed", 0)) if node.get("path") else 0,
                        int(node.get("showOn") == "bubbled"), *area, *pathvalues])
                assert len(info["items"]) - first <= 32, (path, code, "Tutorial runtime capacity")
                rows.append([first, len(info["items"]) - first])
            info["spans"].append(rows)
    return info


def header(info, ids):
    lines = ['struct tutorial { int sprite; float x,y,angle,fadein,hold,fadeout,repeat,delay,speed,trigger; float left,top,width,height,firstx,firsty,lastx,lasty; };',
             'inline constexpr tutorial tutorials[] = {']
    lines += ['{' + str(ids[row[0]]) + ',' + ','.join(str(float(v)) + 'f' for v in row[1:]) + '},' for row in info['items']]
    lines += ['};', 'inline constexpr int tutorialspans[50][12][2] = {']
    lines += ['{' + ','.join('{' + ','.join(map(str, span)) + '}' for span in row) + '},' for row in info['spans']]
    return lines + ['};']
