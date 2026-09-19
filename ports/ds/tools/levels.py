"""Compile the first two original XML boxes without substituting level layouts."""
import hashlib
import json
import xml.etree.ElementTree as xml


def build(content, output, sources):
    def number(value):
        try:
            return str(float(value)) + "f"
        except ValueError:
            return "0.0f"

    def point(x, y):
        return "{" + number(x) + "," + number(y) + "}"

    lines = ['#pragma once', '#include "simulation.hpp"', 'namespace dx {',
             'inline constexpr std::array<level, 50> levels = [] { std::array<level, 50> items{};']
    audit = []
    for box in range(1, 3):
        for index in range(1, 26):
            path = content / "maps" / f"{box}_{index}.xml"
            sources.add(path)
            document = xml.parse(path).getroot()
            settings = document.find("./layer[@name='settings']/map")
            design = document.find("./layer[@name='settings']/gameDesign")
            objects = document.find("./layer[@name='Objects']")
            width, height = float(settings.get("width")) * 3, float(settings.get("height")) * 3
            offset = (2560 - width) / 2
            tags = {}
            lines.append(f"{{ auto& value = items[{(box - 1) * 25 + index - 1}];")
            lines.append(f"value.left = {number(offset)}; value.width = {number(width)}; value.height = {number(height)};")
            lines.append(f"value.speed = {number(float(design.get('ropePhysicsSpeed', '1')) * 1.4)};")
            lines.append(f"value.box = {box - 1}; value.index = {index - 1};")
            assert design.get("twoParts", "false") == "false", path

            def position(node):
                return point(float(node.get("x")) * 3 + offset, float(node.get("y")) * 3)

            def motion(node):
                values = [float(v) for v in node.get("path", "0,0").split(",") if v]
                assert len(values) == 2, (path, node.attrib)
                return "{" + point(values[0], values[1]) + "," + number(node.get("moveSpeed", 0)) + "," + number(node.get("rotateSpeed", 0)) + "}"

            for node in objects:
                if node.tag.startswith("tutorial"):
                    continue
                ordinal = tags.get(node.tag, 0)
                tags[node.tag] = ordinal + 1
                if node.tag in ("candy", "target"):
                    assert ordinal == 0
                    lines.append(f"value.{node.tag} = {position(node)};")
                elif node.tag == "grab":
                    assert ordinal < 8 and node.get("wheel", "false") == "false" and node.get("gun", "false") == "false"
                    assert float(node.get("moveLength", -1)) <= 0 and not node.get("path")
                    radius = float(node.get("radius", -1))
                    radius = radius * 3 if radius != -1 else -1
                    spider = node.get("spider") == "true"
                    lines.append(f"value.hooks[{ordinal}] = {{{position(node)},{number(float(node.get('length')) * 3)},{number(radius)},{str(spider).lower()}}};")
                elif node.tag == "star":
                    assert ordinal < 3
                    lines.append(f"value.stars[{ordinal}] = {position(node)}; value.timeouts[{ordinal}] = {number(node.get('timeout', -1))}; value.starmotions[{ordinal}] = {motion(node)};")
                elif node.tag == "bubble":
                    assert ordinal < 24
                    lines.append(f"value.bubbles[{ordinal}] = {position(node)};")
                elif node.tag == "pump":
                    assert ordinal < 8
                    lines.append(f"value.pumps[{ordinal}] = {{{position(node)},{number(float(node.get('angle', 0)) + 90)}}};")
                elif node.tag in ("spike1", "spike2", "spike3", "spike4"):
                    ordinal = sum(v for k, v in tags.items() if k.startswith("spike")) - 1
                    assert ordinal < 8 and node.get("toggled", "false") == "false"
                    lines.append(f"value.spikes[{ordinal}] = {{{position(node)},{motion(node)},{number(node.get('angle', 0))},{node.get('size')}}};")
                else:
                    raise ValueError((path, "Unsupported object", node.tag))
            assert tags.get("star") == 3 and tags.get("candy") == 1 and tags.get("target") == 1
            lines.append(f"value.hookcount = {tags.get('grab', 0)}; value.bubblecount = {tags.get('bubble', 0)}; value.pumpcount = {tags.get('pump', 0)}; value.spikecount = {sum(v for k,v in tags.items() if k.startswith('spike'))}; }}")
            audit.append(dict(map=path.stem, sha256=hashlib.sha256(path.read_bytes()).hexdigest(), objects=tags, width=width, height=height))
    lines += ['return items; }();', 'inline constexpr const level& firstlevel = levels[0];', '}']
    (output / "level.hpp").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (output / "levelmanifest.json").write_text(json.dumps(audit, indent=2), encoding="utf-8")


if __name__ == "__main__":
    from assets import content, output
    build(content, output, set())
