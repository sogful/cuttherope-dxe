"""Checks source registrations for streamed voices, star pickups and P2 seams."""

import audioop
import hashlib
import json
import math
from pathlib import Path
import re
import soundfile
import wave
import xml.etree.ElementTree as xml
from PIL import Image

import colors
from levels import boxes

root = Path(__file__).resolve().parents[1]
repo, generated = root.parents[1], root / "generated"
content = repo / "content"
voice = json.loads((generated / "voicemanifest.json").read_text())
for name in ("game", "menu"):
    samples, rate = soundfile.read(content / f"sounds/{name}_music.flac", dtype="int16", always_2d=True)
    pcm = samples.astype("<i2", copy=False).tobytes()
    if samples.shape[1] == 2: pcm=audioop.tomono(pcm,2,.5,.5)
    pcm,_ = audioop.ratecv(pcm,2,1,rate,11025,None)
    pcm = audioop.lin2lin(pcm,2,1)
    pcm += b"\0"*(-len(pcm)%4)
    assert (generated / f"nitro/{name}music.bin").read_bytes()==pcm
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
    ("MonsterSleep1", "Sleep01"),
    ("MonsterSleep2", "Sleep02"),
    ("MonsterSleep3", "Sleep03"),
]
for skin, config in enumerate(configs):
    for index, (event, suffix) in enumerate(events):
        unique = event in config.get("uniqueSounds", [])
        if 4 <= index < 6 and not unique:
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
effectnames = ("mouse_rustle", "mouse_idle", "mouse_tap", "star_light01", "star_light02",
               "transporter_drop", "transporter_move", "transporter_click1", "transporter_click2",
               "transporter_click3", "transporter_click4")
effecttable = re.search(r"streameffects\[\] = \{(.*?)\};", (generated / "assets.hpp").read_text()).group(1)
effects = [tuple(map(int, pair)) for pair in re.findall(r"\{(\d+),(\d+)\}", effecttable)]
assert len(effects) == len(effectnames)
for name, (offset, size) in zip(effectnames, effects):
    with wave.open(str(content / "sounds/sfx" / (name + ".wav")), "rb") as sound:
        pcm = sound.readframes(sound.getnframes()); width = sound.getsampwidth()
        if sound.getnchannels() == 2: pcm = audioop.tomono(pcm, width, .5, .5)
        pcm, _ = audioop.ratecv(pcm, width, 1, sound.getframerate(), 16000, None)
        pcm = audioop.lin2lin(pcm, width, 2)
    pcm += b"\0" * (-len(pcm) % 4)
    assert data[offset:offset + size] == pcm, name
    assert size <= voice["maximum"]
import backgroundstore
world = backgroundstore.read(generated,"world")
packs = json.loads((content / "ctroriginal_packs.json").read_text())
for entry in backgrounds:
    box, sections = entry["box"], entry["sections"]
    config = packs[box]
    assert (
        entry["seamY"] == config.get("boxBackgroundP2Y", 0)
        and entry["resources"] == config["boxBackground"]
    )
    image = Image.open(generated / f"background{box+1}x{sections}.png").convert("RGB")
    assert image.size == (256, sections * 192 + 64)
    source = Image.open(content / "images/backgrounds" / (config["boxBackground"][0] + ".png"))
    assert entry["coverScale"] == max(1920/source.width,1440/source.height)
    assert Image.open(generated / f"background{box+1}x{sections}.png").getextrema()[3][0] >= 254, "Background cover fit left transparent gaps"
    assert world[
        entry["offset"] : entry["offset"] + image.width * image.height * 2
    ] == colors.direct(image)
    if sections > 1 and len(config["boxBackground"]) > 1:
        ordinary = Image.open(generated / f"background{box+1}x1.png").convert("RGB")
        assert (
            image.crop((0, 0, 256, 256)).tobytes() != ordinary.tobytes()
        ), "Missing authored seam overlay"
assert len(backgrounds) == boxes * 3
for box in range(1, boxes + 1):
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
    f"PASS: {len(records)} exact source voice clips/fallbacks, {len(effects)} streamed effects, {len(backgrounds)} seam composites, {boxes * 25} background windows, 13 restored sparkle frames and 12 lock-width tables"
)
