"""Pillow 16-1 sleep, illumination and feeding, using only real controls."""
import json


def check(run, tap, key, touch, state, framebuffer, settle, snapshot, report, directory, costume):
    tap(128,170); tap(131,186); key(0); key(8)
    for _ in range(15): key(7)
    run(180); key(8); tap(66,26); settle()
    assert state()["level"] == 375
    frames, rows = [], []

    def record():
        run(1)
        rows.append(state())
        if len(rows)%2 == 0: frames.append(framebuffer().crop((0,192,256,384)))

    for _ in range(180): record()
    assert all(not row["awake"] and not row["mouth"] and row["state"]==0 for row in rows)
    snapshot(f"pillow-{costume}-sleeping")
    touch(118,65); touch(138,65); touch(138,65,False)
    for _ in range(900):
        record()
        if state()["awake"]: break
    assert state()["awake"] and not state()["mouth"] and state()["state"]==0,state()
    for _ in range(90): record()
    snapshot(f"pillow-{costume}-awake")
    touch(92,36); touch(112,36); touch(112,36,False)
    for _ in range(900):
        record()
        if state()["state"]==1: break
    assert state()["state"]==1,state()
    snapshot(f"pillow-{costume}-fed")
    frames[0].save(directory/f"pillow-{costume}.gif",save_all=True,append_images=frames[1:],duration=34,loop=0)
    openings=sum(bool(row["mouth"]) and not rows[i-1]["mouth"] for i,row in enumerate(rows) if i)
    assert openings==1,openings
    report.update(passed=True,costume=costume,mouthOpenings=openings,rows=rows)
    (directory/f"nightreport-{costume}.json").write_text(json.dumps(report,indent=2))
    print(f"PASS: Pillow costume {costume}: asleep while unlit, bulb-only wake without eating, one mouth opening and real candy win")
