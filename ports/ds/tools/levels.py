"""Compile original maps and compact runtime records, rejecting unsupported mechanics."""
import hashlib
import json
import math
import struct
import xml.etree.ElementTree as xml

boxes = 14


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
    audit, packed, offsets, routes, routepoints = [], [], [], [], []
    f = lambda value: struct.unpack("<f", struct.pack("<f", value))[0]
    limits = dict(hooks=16, bubbles=32, spikes=16, pumps=8, hats=8, bouncers=16, switches=4, discs=4, ghosts=4, tubes=6, lanterns=6)
    for box in range(1, boxes + 1):
        for index in range(1, 26):
            path = content / "maps" / f"{box}_{index}.xml"
            sources.add(path)
            document = xml.parse(path).getroot()
            settings = document.find("./layer[@name='settings']/map")
            design = document.find("./layer[@name='settings']/gameDesign")
            objects = [node for layer in document.findall('layer') if layer.get('name') != 'settings' for node in layer]
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
                if not node.get("path"):
                    return [[0.0,0.0],0.0,0.0,0.0,-1]
                pathvalue = node.get("path", "0,0")
                circle = 0.0
                if pathvalue.startswith("R"):
                    circle = float(pathvalue[2:]) * 3 * (1 if pathvalue[1] == "C" else -1)
                    values = [0.0,0.0]
                else:
                    values = [number(v) * 3 for v in pathvalue.rstrip(",").split(",")]
                route = -1
                if len(values) > 2:
                    assert len(values)%2 == 0, (path,node.attrib)
                    route = len(routes)
                    points = [[0.0,0.0]] + [values[i:i+2] for i in range(0,len(values),2)]
                    routes.append([len(routepoints),len(points),False]); routepoints.extend(points)
                    values = [0.0,0.0]
                return [values, float(int(float(node.get("moveSpeed", 0)) * 3.3)), float(int(float(node.get("rotateSpeed", 0)))), circle, route]

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
                    assert node.get("gun", "false") == "false", (path,node.attrib)
                    for flag in ("kickable", "invisible", "helicopter"):
                        assert node.get(flag, "false") == "false", (path,node.attrib)
                    route = -1
                    if node.get("path"):
                        route = len(routes)
                        origin, points, value = position(node), [], node.get("path")
                        if value.startswith("R"):
                            radius = int(value[2:]) * 3
                            count, angle = radius // 2, 0.0
                            step = f(f(math.tau) / count) * (1 if value[1] == "C" else -1)
                            for _ in range(count):
                                points.append([f(origin[0] + f(radius * f(math.cos(angle)))), f(origin[1] + f(radius * f(math.sin(angle))))])
                                angle = f(angle + step)
                        else:
                            points.append(origin)
                            values = list(map(number,value.rstrip(",").split(",")))
                            assert len(values) % 2 == 0
                            points += [[f(origin[0] + f(values[i] * 3)),f(origin[1] + f(values[i+1] * 3))] for i in range(0,len(values),2)]
                        routes.append([len(routepoints),len(points),value.startswith('R')])
                        routepoints.extend(points)
                    radius = float(node.get("radius", -1))
                    radius = radius * 3 if radius != -1 else -1.0
                    records["hooks"].append([position(node), float(node.get("length", 0)) * 3, radius, node.get("spider") == "true",
                        0.0 if route >= 0 else max(0.0, float(node.get("moveLength", -1)) * 3), float(node.get("moveOffset", 0)) * 3,
                        node.get("moveVertical") == "true", int(node.get("part") != "L"), node.get("wheel") == "true",
                        route, float(int(float(node.get("moveSpeed", 0)) * 3.3)), node.get("hidePath") == "true"])
                elif node.tag == "star":
                    stars.append(position(node)); timeouts.append(float(node.get("timeout", -1))); motions.append(motion(node))
                elif node.tag == "bubble":
                    records["bubbles"].append(position(node))
                elif node.tag == "pump":
                    records["pumps"].append([position(node), float(node.get("angle", 0)) + 90])
                elif node.tag in ("spike1", "spike2", "spike3", "spike4", "electro"):
                    toggle = node.get("toggled", "false")
                    group = -1 if toggle == "false" else int(toggle)
                    records["spikes"].append([position(node), motion(node), number(node.get("angle", 0)), int(node.get("size")),
                        float(node.get("onTime",0)), float(node.get("offTime",0)), float(node.get("initialDelay",0)), group])
                elif node.tag == "sock":
                    records["hats"].append([position(node), motion(node), number(node.get("angle",0)) + 90,
                        int(node.get("group",0)), box == 4 and index == 25])
                elif node.tag in ("bouncer1", "bouncer2"):
                    records["bouncers"].append([position(node), motion(node), number(node.get("angle",0)), int(node.get("size"))])
                elif node.tag == "gravitySwitch":
                    records["switches"].append(position(node))
                elif node.tag == "rotatedCircle":
                    records["discs"].append([position(node), int(node.get("size")), int(node.get("handleAngle", 0)), node.get("oneHandle") == "true"])
                elif node.tag == "ghost":
                    radius = float(node.get("radius", -1))
                    forms = 1 + sum(flag for name, flag in (("bubble", 2), ("grab", 4), ("bouncer", 8)) if node.get(name) == "true")
                    records["ghosts"].append([position(node), radius * 3 if radius != -1 else -1.0, number(node.get("angle", 0)), forms])
                elif node.tag == "steamTube":
                    records["tubes"].append([position(node), number(node.get("angle", 0)), 3.0])
                elif node.tag == "lantern":
                    route = -1
                    movement = motion(node)
                    if node.get("path"):
                        route = len(routes)
                        origin, points, value = position(node), [], node.get("path")
                        if value.startswith("R"):
                            radius = int(value[2:]) * 3
                            count, angle = radius // 2, 0.0
                            step = f(f(math.tau) / count) * (1 if value[1] == "C" else -1)
                            for _ in range(count):
                                points.append([f(origin[0] + f(radius * f(math.cos(angle)))), f(origin[1] + f(radius * f(math.sin(angle))))])
                                angle = f(angle + step)
                        else:
                            points = [origin, [f(origin[k] + movement[0][k]) for k in (0,1)]]
                        routes.append([len(routepoints),len(points),value.startswith("R")])
                        routepoints.extend(points)
                    records["lanterns"].append([position(node), movement, node.get("candyCaptured") == "true", route])
                elif node.tag in ("hidden02", "hidden03", "hiddenElement", "spikesSwitch"):
                    pass  # The C# LoadObjects switch also ignores this legacy map tag.
                else:
                    raise ValueError((path, "Unsupported object", node.tag))
            assert len(stars) == 3 and target is not None, path
            assert (tags.get("candyL") == tags.get("candyR") == 1) if split else tags.get("candy") == 1 or any(item[2] for item in records["lanterns"])
            if split:
                candy = [(halves[0][axis] + halves[1][axis]) / 2 for axis in (0,1)]
            lines.append(f"{{ auto& value = items[{(box-1)*25+index-1}];")
            for key, value in dict(left=left, width=width, height=height, speed=speed, box=box-1, index=index-1,
                                   candy=candy, target=target, split=split,
                                   gravity=[float(design.get("globalGravityX", 0)), float(design.get("globalGravityY", 784))]).items():
                lines.append(f"value.{key} = {literal(value)};")
            for i in range(2): lines.append(f"value.halves[{i}] = {literal(halves[i])};")
            for i in range(3):
                lines.append(f"value.stars[{i}] = {literal(stars[i])}; value.timeouts[{i}] = {literal(timeouts[i])}; value.starmotions[{i}] = {literal(motions[i])};")
            offsets.append(len(packed))
            packed += flatten([left,width,height,speed,box-1,index-1,candy,target,split,halves,
                float(design.get("globalGravityX", 0)),float(design.get("globalGravityY", 784))])
            for i in range(3): packed += flatten([stars[i], timeouts[i], motions[i]])
            countnames = dict(hooks="hookcount",bubbles="bubblecount",spikes="spikecount",pumps="pumpcount",hats="hatcount",bouncers="bouncercount",switches="switchcount",discs="disccount",ghosts="ghostcount",tubes="tubecount",lanterns="lanterncount")
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
    header = ['#pragma once', '#include "simulation.hpp"', 'namespace dx {', 'struct route { int first, count; bool circle; };', 'inline constexpr route routes[] = {']
    header += [literal(item) + ',' for item in routes]
    header += ['};', 'inline constexpr point routepoints[] = {']
    header += [literal(item) + ',' for item in routepoints]
    (output / "routes.hpp").write_text('\n'.join(header + ['};','}']) + '\n', encoding="utf-8")


if __name__ == "__main__":
    from assets import content, output
    build(content, output, set())
