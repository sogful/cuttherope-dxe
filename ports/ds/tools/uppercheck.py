"""Actual dual-screen output checks, using only normal menu and stylus input."""

import json
from PIL import Image, ImageChops, ImageStat
import statistics
from pathlib import Path


def check(run,tap,key,touch,state,framebuffer,settle,snapshot,report,directory):
    layout=json.loads((Path(__file__).resolve().parents[1]/"generated/menumanifest.json").read_text(encoding="utf-8"))
    grid=layout["levelpositions"]
    leave=layout["gameui"]["pause"][2]
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
    tap(*grid[14])
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
    key(3); tap(*leave); settle(); key(0)
    for _ in range(7): key(7)
    run(120); key(8); tap(*grid[2]); settle()
    assert state()["level"]==177
    touch(100,66); touch(155,66); touch(155,66,False)
    rising=[]; heights=[]
    for _ in range(900):
        run(1)
        if state()["y"]<0:
            rising.append(framebuffer()); heights.append(state()["y"])
        if state()["failure"]==1: break
    assert state()["failure"]==1 and state()["y"]<-400 and len(rising)>8,state()
    run(5); snapshot("upper-candy-retired")
    cx=round(128+(state()["x"]-1280)*192/1440)
    cy=round(192+state()["y"]*192/1440)
    candy=top().crop((cx-7,cy-7,cx+8,cy+8))
    red=sum(r>80 and r>g*1.5 and r>b*1.5 for r,g,b in candy.getdata())
    assert red==0,("Frozen candy remained above the level",red,state())
    record("upper-candy-fade",rising)
    key(3); tap(*leave); settle(); key(0)
    for _ in range(9): key(7)
    run(120); key(8); tap(*grid[0]); settle()
    assert state()["level"]==400
    snapshot("upper-mechanical-background")
    key(3); touch(*leave); touch(*leave,False)
    closing=[]; ages=[]
    for _ in range(180):
        run(1); closing.append(framebuffer()); ages.append(state()["doorframe"] if state()["door"]==2 else -1)
        if state()["view"]==4 and not state()["transition"]: break
    record("upper-mechanical-closing",closing)
    comparisons={}
    for lag in range(-3,4):
        errors=[]
        for index,age in enumerate(ages):
            if not 19<=age<=29 or not 0<=index+lag<len(closing): continue
            above=closing[index].crop((0,128,24,176)).transpose(Image.Transpose.FLIP_TOP_BOTTOM)
            below=closing[index+lag].crop((0,208,24,256))
            errors.append(sum(ImageStat.Stat(ImageChops.difference(above,below)).mean)/3)
        if errors: comparisons[lag]=statistics.median(errors)
    report["flapLagErrors"]=comparisons
    print("FLAP:",comparisons,flush=True)
    assert comparisons and min(comparisons,key=comparisons.get)==0,("Mechanical flap timing drift",comparisons)
    report["upperCandyRetiredRedPixels"]=red
    report.update(passed=True,upperChecks=True,scrollCameraPositions=len(cameras))
    (directory/"upperreport.json").write_text(json.dumps(report,indent=2))
    print("PASS: native photo/shadow, upper HUD >=50 updates/s, dual flashes, completion/flaps, tall camera, upper candy fade and synchronized Mechanical flaps")
