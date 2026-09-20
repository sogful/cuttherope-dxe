"""Checks source registrations for streamed voices, star pickups and P2 seams."""

import audioop
import hashlib
import json
import math
from pathlib import Path
import re
import wave
import xml.etree.ElementTree as xml
from PIL import Image

import colors

root = Path(__file__).resolve().parents[1]
repo, generated = root.parents[1], root / "generated"
content = repo / "content"
voice = json.loads((generated / "voicemanifest.json").read_text())
resourcepath = repo / "src/CutTheRopeDX.Core/GameMain/Resources.cs"
assert voice["resourcesHash"] == hashlib.sha256(resourcepath.read_bytes()).hexdigest()
resources = dict(
    re.findall(r'public const string (\w+) = "([^"]+)";', resourcepath.read_text())
)
configs = [{}] + json.loads(
    (content / "images/animations/om_nom_skins.json").read_text()
)
records = {(item["skin"], item["event"]): item for item in voice["records"]}
data = (generated / "nitro/voices.bin").read_bytes()
events = [
    ("MonsterOpen", "MouthOpen"),
    ("MonsterClose", "MouthClose"),
    ("MonsterChewing", "Chewing"),
    ("MonsterSad", "Sad"),
    ("MonsterExcited", "Excited"),
    ("MonsterGreeting", "Greeting"),
]
for skin, config in enumerate(configs):
    for index, (event, suffix) in enumerate(events):
        unique = event in config.get("uniqueSounds", [])
        if index >= 4 and not unique:
            assert (skin, event) not in records
            continue
        expected = resources[event]
        if unique and config.get("name"):
            expected = resources.get("TT" + config["name"] + suffix, expected)
        entry = records[(skin, event)]
        assert entry["resource"] == expected
        with wave.open(
            str(content / "sounds/sfx" / (expected + ".wav")), "rb"
        ) as sound:
            pcm = sound.readframes(sound.getnframes())
            width = sound.getsampwidth()
            if sound.getnchannels() == 2:
                pcm = audioop.tomono(pcm, width, 0.5, 0.5)
            pcm, _ = audioop.ratecv(pcm, width, 1, sound.getframerate(), 16000, None)
            pcm = audioop.lin2lin(pcm, width, 2)
        pcm += b"\0" * (-len(pcm) % 4)
        assert data[entry["offset"] : entry["offset"] + entry["size"]] == pcm
        assert entry["size"] <= voice["maximum"]
backgrounds = json.loads((generated / "backgroundmanifest.json").read_text())
world = (generated / "nitro/world.bin").read_bytes()
packs = json.loads((content / "ctroriginal_packs.json").read_text())
for entry in backgrounds:
    box, sections = entry["box"], entry["sections"]
    config = packs[box]
    assert (
        entry["seamY"] == config["boxBackgroundP2Y"]
        and entry["resources"] == config["boxBackground"]
    )
    image = Image.open(generated / f"background{box+1}x{sections}.png").convert("RGB")
    assert image.size == (256, sections * 192 + 64)
    assert world[
        entry["offset"] : entry["offset"] + image.width * image.height * 2
    ] == colors.direct(image)
    if sections > 1:
        ordinary = Image.open(generated / f"background{box+1}x1.png").convert("RGB")
        assert (
            image.crop((0, 0, 256, 256)).tobytes() != ordinary.tobytes()
        ), "Missing authored seam overlay"
for box in range(1, 7):
    for level in range(1, 26):
        node = xml.parse(content / f"maps/{box}_{level}.xml").find("./layer/map")
        height = float(node.get("height")) * 3
        sections = math.ceil(height / 1440)
        assert 1 <= sections <= 3
        maximumtop = round((height - 1440) * 192 / 1440) // 64 * 64
        assert maximumtop + 256 <= sections * 192 + 64
menus = json.loads((generated / "menumanifest.json").read_text())
stars = [s for s in menus["sprites"] if s["name"].startswith("starburst")]
assert len(stars) == 13
for i, sprite in enumerate(stars):
    assert (
        sprite["source"]["resource"] == "obj_star_disappear"
        and sprite["source"]["quad"] == i
        and sprite["source"]["restore"]
    )
assert len(menus["lockwidths"]) == 12 and all(
    len(row) == 17 for row in menus["lockwidths"]
)
print(
    f"PASS: {len(records)} exact source voice clips/fallbacks, 18 seam composites, 150 background windows, 13 restored sparkle frames and 12 lock-width tables"
)
