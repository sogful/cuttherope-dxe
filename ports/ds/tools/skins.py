import hashlib
import json
import re
import os
import subprocess
from pathlib import Path

from PIL import Image
import uiscale


def build(menu):
    quad, add = menu["quad"], menu["add"]
    root, content = menu["root"], menu["content"]
    scale, fit = menu["scale"], menu["fit"]
    previewfit = fit*uiscale.picker
    info = {"previews": [], "candies": [], "fragments": [], "halves": [], "costumes": [], "animations": [], "sleeptrim": [], "sources": {}}
    for i in range(67):
        quad("particle" + str(i), "traces_ctr2", i, 1, restore=False, group="particles" + str(i // 5))
    for i in range(3):
        quad("traceglow" + str(i), "traces_ctr2_glow", i, 1, restore=False, group="traceglow" + str(i))
    path = root.parents[1] / "src/CutTheRopeDX.Core/GameMain/FingerTraces/NamedTracePresets.cs"
    presets = {}
    for name, body in re.findall(r"public static FingerParticles Create(\w+)Particles\([^)]*\).*?new FingerParticlesConfig\((.*?)\)\);", path.read_text(), re.S):
        presets[name] = dict(re.findall(r"(\w+):\s*([^,\n]+)", body))
    bindings = [("Bubble", {}), ("Lightning", {}), ("Star", {}), ("Winter", {}),
                ("Red", {"alpha": ".3", "blendMode": "FingerTraceBlendMode.Additive"}),
                ("Red", {"alpha": ".75", "blendMode": "FingerTraceBlendMode.Alpha"})]
    bindings += [("Alpha", {"firstQuad": str(a), "quadCount": str(b)}) for a, b in [(52, 10), (43, 9), (39, 4), (62, 5), (30, 9)]]
    info["presets"] = [{key: binding.get(value, value) for key, value in presets[name].items()} for name, binding in bindings]
    info["sources"][str(path.relative_to(root.parents[1]))] = hashlib.sha256(path.read_bytes()).hexdigest()
    for index in range(6):
        quad("skin" + str(index), "skin_selection", index, factor=previewfit,
             pixels=(60,29) if index>=4 else None)
    for tab, count in enumerate((52, 9, 16, 11)):
        row = []
        for index in range(count):
            if tab == 2:
                continue
            name = "preview" + str(tab) + "x" + str(index)
            resource = "fingertrace_skin" if tab == 3 else "skin_selection"
            frame = index if tab == 3 else index + (6 if tab == 0 else 60)
            quad(name, resource, frame, factor=previewfit, restore=tab == 3, group="previews" + str(tab) + "x" + str(index // 8))
            row.append(name)
        info["previews"].append(row)
    for index in range(52):
        resource = "candies/obj_candy_01_new" if index == 0 else "candies/obj_candy_" + str(index + 1).zfill(2)
        names = []
        for layer in range(3):
            name = "gamecandy" + str(index) + "x" + str(layer)
            quad(name, resource, layer, .71, restore=True, group="gamecandy" + str(index))
            names.append(name)
        info["candies"].append(names)
        fragments = []
        for layer in range(3, 8):
            name = "gamefragment" + str(index) + "x" + str(layer)
            quad(name, resource, layer, .71, restore=True, group="gamecandy" + str(index))
            fragments.append(name)
        info["fragments"].append(fragments)
        halves = []
        for layer in (8, 9):
            name = "gamehalf" + str(index) + "x" + str(layer)
            quad(name, resource, layer, .71, restore=True, group="gamecandy" + str(index))
            halves.append(name)
        info["halves"].append(halves)
    classic = []
    for index in range(19):
        name = "classicpreview" + str(index)
        size = round(640 * scale * .75 * previewfit / 2) * 2
        quad(name, "char_animations", index, .75 * previewfit, restore=True, group="classicpreview"+str(index//6), pixels=(size, size))
        classic.append(name)
    info["classic"] = classic
    info["previews"][2].append(classic[0])
    baked = root.parent / "roblox/generated/omnom-baked"
    indexpath = baked / "index.json"
    if not indexpath.exists():
        baked = root / "generated/omnom-baked"
        indexpath = baked / "index.json"
        if not indexpath.exists():
            environment = os.environ.copy()
            environment["DX_SKIN_EXPORT"] = str(baked)
            environment["DX_CONTENT_ROOT"] = str(content)
            project = root.parents[1] / "src/CutTheRopeDX.Rendering.Skia.Tests/CutTheRopeDX.Rendering.Skia.Tests.csproj"
            subprocess.run(["dotnet", "test", str(project), "-c", "Release", "--filter",
                            "FullyQualifiedName~RobloxSkinExportTests.ExportOriginalXmlAnimations"], env=environment, check=True)
    info["sources"][str(indexpath.relative_to(root.parents[1]))] = hashlib.sha256(indexpath.read_bytes()).hexdigest()
    catalog = json.loads(indexpath.read_text())
    manifest = content / "images/animations/om_nom_skins.json"
    menu["sources"].add(manifest)
    originals = json.loads(manifest.read_text())
    for skin in catalog:
        slot, config = skin["slot"], skin["config"]
        assert config == originals[slot - 1], (slot, "Stale XML bake configuration")
        menu["sources"].add(content / "images/animations" / config["animationXml"])
        states = config["timelines"]
        preview = states.get("IdleVariationThree") if slot == 1 else states.get("Excited", states["IdleLoop"])
        active = next(iter(config["idleVariants"]), states["IdleLoop"])
        chosen = [states["IdleLoop"], states.get("Excited", states["IdleLoop"]), states["MouthOpening"], states["Sad"], states["Chewing"], active, states.get("Greeting", states["IdleLoop"])]
        chosen += [states["Sleeping"], states.get("IdleToSleep",states["Sleeping"])]
        required = set(chosen + [preview])
        pending = list(required)
        for timeline in pending:
            following = config.get("followups", {}).get(str(timeline), -1)
            if following >= 0 and following not in required:
                required.add(following)
                pending.append(following)
        references = {}
        for timeline in sorted(required):
            details = skin["timelines"][str(timeline)]
            frames, previewframes = [], []
            for frame in range(details["frames"]):
                path = baked / str(slot) / str(timeline) / (str(frame) + ".png")
                source = Image.open(path).convert("RGBA")
                size = tuple(round(value * scale) for value in source.size)
                image = source.resize(size, Image.Resampling.LANCZOS)
                name = "costume" + str(slot) + "x" + str(timeline) + "x" + str(frame)
                digest = hashlib.sha256(path.read_bytes()).hexdigest()
                relative = str(path.relative_to(root.parents[1]))
                info["sources"][relative] = digest
                # Four-frame gameplay pages keep a single animated character
                # from pinning 64 KiB during world + flap + result compositing.
                add(name, image, "costume" + str(slot) + "x" + str(timeline) + "x" + str(frame // 4),
                    source={"baked": relative, "sha256": digest, "scale": scale})
                frames.append(name)
                previewname = "slot" + name
                previewsize = tuple(round(value * scale * 1.25 / 1.73 * previewfit / 2) * 2 for value in source.size)
                previewimage = source.resize(previewsize, Image.Resampling.LANCZOS)
                add(previewname, previewimage, "slot" + str(slot) + "x" + str(timeline) + "x" + str(frame // 6),
                    source={"baked": relative, "sha256": digest, "pixels": previewsize, "preview": True})
                previewframes.append(previewname)
            references[timeline] = len(info["animations"])
            following = config.get("followups", {}).get(str(timeline), -1)
            if timeline in (states["IdleLoop"],states["Sleeping"]):
                following = timeline
            info["animations"].append(dict(frames=frames, previewframes=previewframes, fps=details["fps"], duration=details["duration"], followup=following))
            if timeline == preview:
                still = min(len(frames) - 1, int(14 / 30 * 20))
                path = baked / str(slot) / str(timeline) / (str(still) + ".png")
                source = Image.open(path).convert("RGBA")
                image = source.resize(previewsize, Image.Resampling.LANCZOS)
                name = "costumepreview" + str(slot)
                add(name, image, "costumepreviews" + str((slot - 1) // 4))
                info["previews"][2].append(name)
        for index in references.values():
            animation = info["animations"][index]
            animation["followup"] = references.get(animation["followup"], -1)
        info["costumes"].append([references[timeline] for timeline in chosen])
        info["sleeptrim"].append(min(config.get("idleToSleepTrimFrames",0)/30, skin["timelines"][str(chosen[8])]["duration"]) if chosen[8]!=chosen[7] else 0)
    assert len(info["costumes"]) == 15 and len(info["previews"][2]) == 16
    return info


def header(info, ids, fit, scale):
    lines = []
    counts = (52, 9, 16, 11)
    lines += ["inline constexpr int skincounts[] = {52,9,16,11};"]
    fit *= uiscale.picker
    top = 37
    bottom = 168
    row = (int(336 * 1.2 * fit) + 10 * fit) * scale
    values = dict(skintop=top, skinbottom=bottom, skinleft=128 - 1144 * fit * scale / 2,
                  skinpitch=(round(271 * fit) + 20 * fit) * scale, skinrow=row,
                  skinwidth=round(271 * fit) * scale, skinheight=round(336 * fit) * scale)
    lines += [f"inline constexpr float {key} = {value:.8f}f;" for key, value in values.items()]
    lines += ["inline constexpr float skinmax[] = {" + ",".join(f"{max(0, ((count + 3) // 4) * row - 10 * fit * scale - (bottom - top)):.8f}f" for count in counts) + "};"]
    def array(name, values):
        return "inline constexpr int " + name + "[] = {" + ",".join(str(ids[item]) for item in values) + "};"
    for tab, previews in enumerate(info["previews"]):
        lines.append(array("previews" + str(tab), previews))
    lines += ["inline constexpr const int* previews[] = {previews0,previews1,previews2,previews3};"]
    lines += [array("classicpreviews", info["classic"])]
    lines += ["inline constexpr int gamecandies[52][3] = {"]
    lines += ["{" + ",".join(str(ids[item]) for item in values) + "}," for values in info["candies"]]
    lines += ["};", "inline constexpr int gamehalves[52][2] = {"]
    lines += ["{" + ",".join(str(ids[item]) for item in values) + "}," for values in info["halves"]]
    lines += ["};", "inline constexpr int gamefragments[52][5] = {"]
    lines += ["{" + ",".join(str(ids[item]) for item in values) + "}," for values in info["fragments"]]
    lines += ["};", "inline constexpr int titlecandies[] = {" + ",".join(str(ids["titlecandy" + str(i)]) for i in range(52)) + "};"]
    for index, animation in enumerate(info["animations"]):
        lines.append(array("animation" + str(index), animation["frames"]))
        lines.append(array("slotanimation" + str(index), animation["previewframes"]))
    lines += ["struct animation { const int* frames; const int* previewframes; int count; float fps, duration; int followup; };", "inline constexpr animation animations[] = {"]
    for index, animation in enumerate(info["animations"]):
        lines.append(f"{{animation{index},slotanimation{index},{len(animation['frames'])},{float(animation['fps'])}f,{animation['duration']}f,{animation['followup']}}},")
    lines += ["};", "inline constexpr int costumes[15][9] = {"]
    lines += ["{" + ",".join(map(str, values)) + "}," for values in info["costumes"]]
    lines += ["};"]
    lines += ["inline constexpr float sleeptrim[] = {" + ",".join(str(float(value))+"f" for value in info["sleeptrim"]) + "};"]
    fields = list(info["presets"][0])
    lines += ["struct traceconfig { " + " ".join("float " + field.lower() + ";" for field in fields) + " };", "inline constexpr traceconfig tracepresets[] = {"]
    for config in info["presets"]:
        values = []
        for field in fields:
            value = config[field]
            if value in ("true", "FingerTraceBlendMode.Additive"): value = "1"
            elif value in ("false", "FingerTraceBlendMode.Alpha"): value = "0"
            values.append(str(float(value.rstrip("f"))) + "f")
        lines.append("{" + ",".join(values) + "},")
    lines += ["};"]
    return lines
