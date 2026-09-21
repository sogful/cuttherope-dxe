"""Actual dual-screen output checks, using only normal menu and stylus input."""

import json
from PIL import ImageChops, ImageStat


def check(run,tap,key,touch,state,framebuffer,settle,snapshot,report,directory):
    def wait(predicate,limit=1800):
        for _ in range(limit):
            if predicate(state()): return
            run(1)
        raise AssertionError(state())

    def top(): return framebuffer().crop((0,0,256,192))
    def brightness(image): return sum(ImageStat.Stat(image).mean)/3
    def record(name,frames):
        frames[0].save(directory/(name+".gif"),save_all=True,append_images=frames[1:],duration=17,loop=0)

    before=top()
    run(90)
    after=top()
    assert before.crop((87,46,169,144)).tobytes()==after.crop((87,46,169,144)).tobytes(), "Photo moved with the shadow"
    assert ImageChops.difference(before,after).getbbox(), "Menu shadow stopped"
    tap(128,170); tap(131,185)
    assert state()["unlocked"]
    key(0); key(8); key(8); key(8)
    settle(); wait(lambda s:s["ticks"]>=150)
    snapshot("upper-empty-stars")
    start=state(); run(120); end=state()
    report["steadyUpdatesPerSecond"]=(end["frames"]-start["frames"])*60/120
    assert end["frames"]-start["frames"]>=100, ("Upper HUD slowed the simple level below 50 updates/s",start,end)
    touch(202,12); touch(202,12,False)
    flashes=[]
    for _ in range(90):
        run(1); flashes.append(framebuffer())
    assert max(brightness(frame.crop((0,0,256,192))) for frame in flashes)>250
    assert max(brightness(frame.crop((0,192,256,384))) for frame in flashes)>250
    record("upper-white-flash",flashes)
    settle(); wait(lambda s:s["ticks"]>=100)
    touch(100,40); touch(155,40); touch(155,40,False)
    winning=[]
    for _ in range(1800):
        run(1); winning.append(framebuffer())
        if state()["view"]==2 and state()["menuage"]>=65: break
    assert state()["view"]==2 and state()["stars"]==3
    record("upper-completion",winning)
    snapshot("upper-closed-results")
    closed=top(); updates=state()["upperframes"]
    run(120)
    assert top().tobytes()==closed.tobytes() and state()["upperframes"]==updates, "Closed results redrew UI on upper screen"
    key(0); settle()
    assert state()["view"]==4
    tap(190,96)
    scrolling=[]; cameras=set()
    for _ in range(1800):
        run(1)
        current=state()
        if not current["transition"]:
            scrolling.append(framebuffer()); cameras.add(current["cameray"])
        if not current["transition"] and not current["door"] and not current["intro"] and len(scrolling)>120: break
    assert state()["level"]==14 and not state()["intro"] and len(cameras)>25
    record("upper-tall-camera",scrolling)
    snapshot("upper-tall-level")
    report.update(passed=True,upperChecks=True,scrollCameraPositions=len(cameras))
    (directory/"upperreport.json").write_text(json.dumps(report,indent=2))
    print("PASS: fixed native photo / moving shadow, upper HUD >=50 updates/s, dual white flash, completion/flaps, static closed results and tall camera")
