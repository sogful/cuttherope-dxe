"""Synthetic GPU pressure, explicitly not evidence of solving the real puzzle."""

import json
from PIL import ImageStat


def check(run, tap, key, state, framebuffer, settle, stress, profiler, report, directory, box=1, level=23):
    def wait(predicate, limit=2400):
        for _ in range(limit):
            if predicate(state()):
                return
            run(1)
        raise AssertionError(state())

    tap(128, 170)
    tap(131, 185)
    key(0)
    key(8)
    for _ in range(box - 1): key(7)
    run(180)
    key(8)
    level -= 1
    tap(round(128 + (824 + level % 5 * 228 - 1280) * 1.01846195 * 192 / 1440),
        round(96 + (203.5 + level // 5 * 258 - 720) * 1.01846195 * 192 / 1440))
    settle()
    wait(lambda s: s["ticks"] >= 40)
    assert state()["level"] == (box - 1) * 25 + level
    hooks = state()["hooks"]
    start = len(profiler.records)
    firstchange = len(profiler.anomalies)
    stress(15)  # Keep ropes active, raise steam, trigger results, repack and force capture.
    frames = []
    repeated = False
    for _ in range(2000):
        run(1)
        frames.append(framebuffer().crop((0, 192, 256, 384)))
        current = state()
        if current["view"] == 2 and current["menuage"] >= 45 and not repeated:
            stress(3)
            repeated = True
        if current["view"] == 2 and current["menuage"] >= 360:
            break
    assert repeated and state()["view"] == 2 and state()["menuage"] >= 360
    before = state()["resets"]
    tap(98, 125)
    settle()
    run(90)
    assert state()["view"] == 0 and state()["resets"] == before + 1
    rows = profiler.records[start:]
    assert sum(item["holds"] for item in rows) >= 2
    assert not any(item["visibleupload"] or item["gpuerrors"] for item in rows)
    hidden = [item for item in rows if item["view"] == 2 and item["menuage"] >= 33]
    assert hidden and all(item["physics"] == 0 for item in hidden)
    changes = profiler.anomalies[firstchange:]
    assert len(changes) >= 2
    # RGB5 capture drops one 3D color bit, but must not move/replace any pixels.
    assert all(item["live"]["holds"] and -4 <= item["minimumChannelChange"] <=
               item["maximumChannelChange"] <= 0 for item in changes), changes
    brightness = [sum(ImageStat.Stat(image).mean) / 3 for image in frames]
    assert min(brightness) > 30 and max(brightness) < 250
    frames[0].save(directory / "heavy-completion.gif", save_all=True,
                   append_images=frames[1:], duration=17, loop=0)
    report.update(passed=True, synthetic=True, simulatedCompletion=f"{box}-{level + 1} with {hooks} hooks",
                  capturedHolds=sum(item["holds"] for item in rows), minimumBrightness=min(brightness),
                  maximumCaptureChannelLoss=max(-item["minimumChannelChange"] for item in changes),
                  resultFrames=len(hidden), maximumHiddenPhysicsUs=max(item["physics"] for item in hidden))
    (directory / "stressreport.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"PASS: synthetic {box}-{level + 1} completion, two forced capture/repack recoveries, hidden solver idle, replay")
