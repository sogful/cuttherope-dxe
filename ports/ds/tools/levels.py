"""Compile original maps and compact runtime records, rejecting unsupported mechanics."""
import hashlib
import json
import xml.etree.ElementTree as xml

boxes = 6


def build(content, output, sources):
    def number(value):
        try:
            return float(value)
        except ValueError:
            return 0.0

    def literal(value):
        if isinstance(value, (list, tuple)):
            return "{" + ",".join(literal(v) for v in value) + "}"
        if isinstance(value, bool):
            return str(value).lower()
        return str(value) if isinstance(value, int) else str(float(value)) + "f"

    def flatten(value):
        if isinstance(value, (list, tuple)):
            return [n for v in value for n in flatten(v)]
        return [float(value)]

    total = boxes * 25
    lines = ['#pragma once', '#include "simulation.hpp"', '#ifndef __NDS__', 'namespace dx {',
             f'inline constexpr std::array<level, {total}> levels = [] {{ std::array<level, {total}> items{{}};']
    audit, packed, offsets = [], [], []
    limits = dict(hooks=8, bubbles=32, spikes=16, pumps=8, hats=8, bouncers=16)
    for box in range(1, boxes + 1):
        for index in range(1, 26):
            path = content / "maps" / f"{box}_{index}.xml"
            sources.add(path)
            document = xml.parse(path).getroot()
            settings = document.find("./layer[@name='settings']/map")
            design = document.find("./layer[@name='settings']/gameDesign")
            objects = document.find("./layer[@name='Objects']")
            width, height = float(settings.get("width")) * 3, float(settings.get("height")) * 3
            left = (2560 - width) / 2
            dx, dy = float(design.get("mapOffsetX", 0)), float(design.get("mapOffsetY", 0))
            split = design.get("twoParts", "false") == "true"
            speed = float(design.get("ropePhysicsSpeed", 1)) * 1.4
            records = {key: [] for key in limits}
            tags, stars, timeouts, motions = {}, [], [], []
            candy, target, halves = [1280.0,720.0], None, [[0.0,0.0],[0.0,0.0]]

            def position(node):
                return [float(node.get("x")) * 3 + left + dx, float(node.get("y")) * 3 + dy]

            def motion(node):
                pathvalue = node.get("path", "0,0")
                circle = 0.0
                if pathvalue.startswith("R"):
                    circle = float(pathvalue[2:]) * (1 if pathvalue[1] == "C" else -1)
                    values = [0.0,0.0]
                else:
                    values = [number(v) for v in pathvalue.rstrip(",").split(",")]
                assert len(values) == 2, (path, node.attrib)
                return [values, float(node.get("moveSpeed", 0)), float(node.get("rotateSpeed", 0)), circle]

            for node in objects:
                if node.tag.startswith("tutorial"):
                    continue
                tags[node.tag] = tags.get(node.tag, 0) + 1
                if node.tag == "candy":
                    candy = position(node)
                elif node.tag == "target":
                    target = position(node)
                elif node.tag in ("candyL", "candyR"):
                    halves[node.tag == "candyR"] = position(node)
                elif node.tag == "grab":
                    assert node.get("wheel", "false") == node.get("gun", "false") == "false" and not node.get("path"), (path,node.attrib)
                    radius = float(node.get("radius", -1))
                    radius = radius * 3 if radius != -1 else -1.0
                    records["hooks"].append([position(node), float(node.get("length", 0)) * 3, radius, node.get("spider") == "true",
                        max(0.0, float(node.get("moveLength", -1)) * 3), float(node.get("moveOffset", 0)) * 3,
                        node.get("moveVertical") == "true", int(node.get("part") != "L")])
                elif node.tag == "star":
                    stars.append(position(node)); timeouts.append(float(node.get("timeout", -1))); motions.append(motion(node))
                elif node.tag == "bubble":
                    records["bubbles"].append(position(node))
                elif node.tag == "pump":
                    records["pumps"].append([position(node), float(node.get("angle", 0)) + 90])
                elif node.tag in ("spike1", "spike2", "spike3", "spike4", "electro"):
                    assert node.get("toggled", "false") == "false", (path,node.attrib)
                    records["spikes"].append([position(node), motion(node), number(node.get("angle", 0)), int(node.get("size")),
                        float(node.get("onTime",0)), float(node.get("offTime",0)), float(node.get("initialDelay",0))])
                elif node.tag == "sock":
                    records["hats"].append([position(node), motion(node), number(node.get("angle",0)) + 90,
                        int(node.get("group",0)), box == 4 and index == 25])
                elif node.tag in ("bouncer1", "bouncer2"):
                    records["bouncers"].append([position(node), motion(node), number(node.get("angle",0)), int(node.get("size"))])
                elif node.tag == "hidden03":
                    pass  # The C# LoadObjects switch also ignores this legacy map tag.
                else:
                    raise ValueError((path, "Unsupported object", node.tag))
            assert len(stars) == 3 and target is not None
            assert (tags.get("candyL") == tags.get("candyR") == 1) if split else tags.get("candy") == 1
            if split:
                candy = [(halves[0][axis] + halves[1][axis]) / 2 for axis in (0,1)]
            lines.append(f"{{ auto& value = items[{(box-1)*25+index-1}];")
            for key, value in dict(left=left, width=width, height=height, speed=speed, box=box-1, index=index-1,
                                   candy=candy, target=target, split=split).items():
                lines.append(f"value.{key} = {literal(value)};")
            for i in range(2): lines.append(f"value.halves[{i}] = {literal(halves[i])};")
            for i in range(3):
                lines.append(f"value.stars[{i}] = {literal(stars[i])}; value.timeouts[{i}] = {literal(timeouts[i])}; value.starmotions[{i}] = {literal(motions[i])};")
            offsets.append(len(packed))
            packed += flatten([left,width,height,speed,box-1,index-1,candy,target,split,halves])
            for i in range(3): packed += flatten([stars[i], timeouts[i], motions[i]])
            countnames = dict(hooks="hookcount",bubbles="bubblecount",spikes="spikecount",pumps="pumpcount",hats="hatcount",bouncers="bouncercount")
            for key, capacity in limits.items():
                assert len(records[key]) <= capacity, (path,key,len(records[key]),capacity)
                lines.append(f"value.{countnames[key]} = {len(records[key])};")
                packed += flatten([len(records[key]), records[key]])
                for i, value in enumerate(records[key]): lines.append(f"value.{key}[{i}] = {literal(value)};")
            lines.append("}")
            audit.append(dict(map=path.stem, sha256=hashlib.sha256(path.read_bytes()).hexdigest(), objects=tags, width=width, height=height))
    lines += ['return items; }();', 'inline constexpr const level& firstlevel = levels[0];', '}', '#endif']
    (output / "level.hpp").write_text("\n".join(lines) + "\n", encoding="utf-8")
    data = ['#pragma once', 'namespace dx {', f'inline constexpr int levelcount = {total};',
        'inline constexpr unsigned leveloffsets[] = {' + ','.join(map(str,offsets)) + '};', 'inline constexpr float leveldata[] = {']
    data += [','.join(literal(v) for v in packed[i:i+16]) + ',' for i in range(0,len(packed),16)]
    (output / "leveldata.hpp").write_text('\n'.join(data + ['};','}']) + '\n', encoding="utf-8")
    (output / "levelmanifest.json").write_text(json.dumps(audit, indent=2), encoding="utf-8")


if __name__ == "__main__":
    from assets import content, output
    build(content, output, set())
