"""Real-input, read-only-telemetry ROM checks for the reported DS regressions."""

import json
import time
from pathlib import Path
from PIL import ImageStat


def check(
    run, tap, key, touch, state, framebuffer, snapshot, settle, report, directory
):
    start = time.monotonic()
    layout=json.loads((Path(__file__).resolve().parents[1]/"generated/menumanifest.json").read_text(encoding="utf-8"))
    layouts=layout["gameui"]["hud"]
    replaypoint=layout["gameui"]["anchors"][11]
    def hud(): return layouts[state()["locale"]]

    def screen():
        return framebuffer().crop((0, 192, 256, 384))

    def wait(predicate, limit=1800):
        for _ in range(limit):
            if predicate(state()):
                return
            run(1)
        raise AssertionError(state())

    def record(name, frames):
        frames[0].save(
            directory / (name + ".gif"),
            save_all=True,
            append_images=frames[1:],
            duration=17,
            loop=0,
        )
        means = [sum(ImageStat.Stat(frame).mean) / 3 for frame in frames]
        assert min(means) > 20, (name, "black frame", min(means))
        return min(means)

    def leave():
        settle()
        if state()["view"] == 0:
            key(3)
        if state()["view"] == 1:
            tap(*layout["gameui"]["pause"][2])
        else:
            key(0)
        settle()
        assert state()["view"] == 4, state()

    tap(128, 170)
    tap(131, 185)
    key(0)
    key(8)
    carousel = []
    for direction in (7, 7, 6, 6):
        key(direction)
        for _ in range(150):
            run(1)
            carousel.append(screen())
    record("regression-carousel", carousel)
    assert state()["pack"] == 0
    key(8)
    key(8)
    settle()
    run(120)
    before = state()
    touch(*hud()[2:])
    touch(*hud()[2:], False)
    flash = []
    for _ in range(90):
        run(1)
        flash.append(screen())
    assert state()["resets"] == before["resets"] + 1 and state()["flash"] == 0
    assert (
        max(sum(ImageStat.Stat(frame).mean) / 3 for frame in flash) > 250
    ), "No fully white restart frame"
    record("regression-white-restart", flash)
    # Pause during chewing, then hold a HUD press across the result handoff.
    touch(100, 40)
    touch(155, 40)
    touch(155, 40, False)
    wait(lambda s: s["state"] == 1)
    won = state()
    run(24)
    tap(*hud()[:2])
    assert state()["view"] == 1
    paused = state()
    run(45)
    assert state()["visuals"] == paused["visuals"]
    key(3)
    touch(*hud()[:2])
    sequence = []
    waitframes = state()["frames"]
    for _ in range(900):
        run(1)
        sequence.append(screen())
        if state()["view"] == 2:
            break
    assert state()["view"] == 2 and state()["frames"] > waitframes + 25
    touch(*hud()[:2], False)
    for _ in range(500):
        run(1)
        sequence.append(screen())
    assert state()["view"] == 2 and state()["resets"] == won["resets"]
    report["completionMinimumBrightness"] = record("regression-completion", sequence)
    # Obsolete HUD coordinates must not capture controls on the result panel.
    tap(*hud()[:2])
    tap(*hud()[2:])
    key(3)
    assert state()["view"] == 2
    snapshot("regression-results-hud-input")
    touch(*replaypoint)
    touch(*replaypoint,False)
    replay = []
    for _ in range(100):
        run(1)
        replay.append(screen())
    record("regression-replay", replay)
    assert state()["view"] == 0 and state()["resets"] == won["resets"] + 1
    leave()
    # Restart pressed while chewing cancels the pending completion exactly once.
    key(8)
    settle()
    run(80)
    touch(100, 40)
    touch(155, 40)
    touch(155, 40, False)
    wait(lambda s: s["state"] == 1)
    before = state()["resets"]
    tap(*hud()[2:])
    settle()
    run(240)
    assert (
        state()["state"] == 0
        and state()["view"] == 0
        and state()["resets"] == before + 1
    )
    snapshot("regression-aborted-completion")
    leave()
    key(7)
    key(8)
    settle()
    run(120)
    touch(10, 50)
    touch(245, 50)
    touch(245, 50, False)
    wait(lambda s: s["state"] == 2)
    lost = state()
    lossframes = []
    for _ in range(600):
        run(1)
        lossframes.append(screen())
        assert state()["view"] != 3, "Legacy failure panel returned"
        if state()["flash"] == 1:
            break
    assert 60 <= state()["frames"] - lost["frames"] <= 64, (lost, state())
    for _ in range(100):
        run(1)
        lossframes.append(screen())
    assert state()["resets"] == lost["resets"] + 1 and state()["state"] == 0
    assert max(sum(ImageStat.Stat(frame).mean) / 3 for frame in lossframes) > 250
    record("regression-delayed-loss", lossframes)
    snapshot("regression-loss-restarted")
    leave()
    tap(190, 96)
    tall = []
    for _ in range(1300):
        run(1)
        if not state()["transition"]:
            tall.append(screen())
        if (
            not state()["transition"]
            and not state()["door"]
            and not state()["intro"]
            and len(tall) > 100
        ):
            break
    assert state()["level"] == 14 and not state()["intro"]
    record("regression-tall-background", tall)
    snapshot("regression-tall-level")
    leave()
    key(0)
    # Foil 1: let the lifted bubble carry the candy into Om Nom.
    key(7)
    key(7)
    run(180)
    key(8)
    key(8)
    settle()
    run(120)
    touch(90, 96)
    for px in range(90, 172, 2):
        touch(px, 96)
    touch(171, 96, False)
    wait(lambda s: s["bubble"] > 0)
    # Carry the tethered bubble back to Om Nom before cutting it loose.
    touch(170, 96)
    for px in range(170, 89, -1):
        touch(px, 96)
    touch(90, 96, False)
    run(240)
    if state()["state"] == 0:
        touch(75, 75)
        touch(125, 75)
        touch(125, 75, False)
    wait(lambda s: s["state"] == 1)
    sequence = []
    for _ in range(750):
        run(1)
        sequence.append(screen())
    assert state()["view"] == 2
    record("regression-foil-completion", sequence)
    snapshot("regression-foil-results")
    leave()
    key(0)
    key(7)
    key(7)
    run(180)
    key(8)
    key(8)
    settle()
    wait(lambda s: s["ticks"] >= 120)
    touch(97, 35)
    touch(164, 35)
    touch(164, 35, False)
    wait(lambda s: s["merges"] == 1)
    touch(114, 73)
    touch(146, 73)
    touch(146, 73, False)
    wait(lambda s: s["state"] == 1)
    valentine = state()
    sequence = []
    for _ in range(1100):
        run(1)
        sequence.append(screen())
    assert state()["view"] == 2 and state()["stars"] == 3
    assert state()["frames"] > valentine["frames"] + 400
    if state()["costume"]:
        assert (
            state()["voices"] > 0 and (state()["voice"] - 1) // 6 == state()["costume"]
        )
    record("regression-valentine", sequence)
    snapshot("regression-valentine-results")
    report.update(passed=True, seconds=time.monotonic() - start)
    (directory / ("regressionreport-" + str(state()["costume"]) + ".json")).write_text(
        json.dumps(report, indent=2)
    )
    print(
        "PASS: white restart, delayed loss, chewing pause/restart, held HUD across completion, full results/replay, tall background, Foil/Valentine completion and costume voices"
    )
