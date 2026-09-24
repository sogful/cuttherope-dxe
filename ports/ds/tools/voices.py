import audioop
import hashlib
import json
import re
import wave


def build(content, output, sources):
    configpath = content / "images/animations/om_nom_skins.json"
    resourcepath = content.parent / "src/CutTheRopeDX.Core/GameMain/Resources.cs"
    sources.add(configpath)
    resources = dict(
        re.findall(r'public const string (\w+) = "([^"]+)";', resourcepath.read_text())
    )
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
    data, cached, rows, records = bytearray(), {}, [], []
    for skin, config in enumerate([{}] + json.loads(configpath.read_text())):
        row = []
        for index, (classic, suffix) in enumerate(events):
            unique = classic in config.get("uniqueSounds", [])
            resource = resources[classic]
            if 4 <= index < 6 and not unique:
                row.append((0, 0))
                continue
            if unique and config.get("name"):
                resource = resources.get("TT" + config["name"] + suffix, resource)
            if resource not in cached:
                path = content / "sounds/sfx" / (resource + ".wav")
                sources.add(path)
                with wave.open(str(path), "rb") as sound:
                    pcm = sound.readframes(sound.getnframes())
                    width = sound.getsampwidth()
                    if sound.getnchannels() == 2:
                        pcm = audioop.tomono(pcm, width, 0.5, 0.5)
                    pcm, _ = audioop.ratecv(
                        pcm, width, 1, sound.getframerate(), 16000, None
                    )
                    pcm = audioop.lin2lin(pcm, width, 2)
                pcm += b"\0" * (-len(pcm) % 4)
                cached[resource] = (len(data), len(pcm))
                data.extend(pcm)
            offset, size = cached[resource]
            row.append((offset, size))
            records.append(
                dict(
                    skin=skin,
                    event=classic,
                    resource=resource,
                    offset=offset,
                    size=size,
                )
            )
        rows.append(row)
    effects = []
    for resource in ("mouse_rustle", "mouse_idle", "mouse_tap", "star_light01", "star_light02",
                     "transporter_drop", "transporter_move", "transporter_click1", "transporter_click2",
                     "transporter_click3", "transporter_click4"):
        path = content / "sounds/sfx" / (resource + ".wav")
        sources.add(path)
        with wave.open(str(path), "rb") as sound:
            pcm = sound.readframes(sound.getnframes()); width = sound.getsampwidth()
            if sound.getnchannels() == 2: pcm = audioop.tomono(pcm,width,.5,.5)
            pcm, _ = audioop.ratecv(pcm,width,1,sound.getframerate(),16000,None)
            pcm = audioop.lin2lin(pcm,width,2)
        pcm += b"\0" * (-len(pcm)%4)
        effects.append((len(data),len(pcm))); data.extend(pcm)
    maximum = max(size for _, size in list(cached.values())+effects)
    (output / "nitro/voices.bin").write_bytes(data)
    (output / "voicemanifest.json").write_text(
        json.dumps(
            dict(
                records=records,
                maximum=maximum,
                resourcesHash=hashlib.sha256(resourcepath.read_bytes()).hexdigest(),
            ),
            indent=2,
        )
    )
    return (
        [
            "struct voice { unsigned offset, size; };",
            f"inline constexpr unsigned voicemax = {maximum};",
            "inline constexpr voice voices[16][9] = {",
        ]
        + [
            "{" + ",".join("{" + str(a) + "," + str(b) + "}" for a, b in row) + "},"
            for row in rows
        ]
        + ["};", "inline constexpr voice streameffects[] = {" + ",".join("{"+str(a)+","+str(b)+"}" for a,b in effects) + "};"]
    )
