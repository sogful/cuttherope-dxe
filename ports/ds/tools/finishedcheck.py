"""Normal UI navigation; final puzzle completion is explicitly synthetic."""
import json


def check(run,tap,key,touch,state,framebuffer,settle,snapshot,finish,report,directory,layout):
    def wait(predicate,limit=1800):
        for _ in range(limit):
            if predicate(state()): return
            run(1)
        raise AssertionError(state())

    tap(128,170); tap(131,185)
    key(0); key(8)
    for _ in range(16): key(7)
    run(180); key(8)
    assert state()["view"]==4 and state()["pack"]==16
    snapshot("mechanical-grid")
    tap(*layout["levelpositions"][24]); settle()
    assert state()["level"]==424 and state()["view"]==0
    key(3); snapshot("mechanical-pause"); key(3)
    finish()
    wait(lambda s:s["view"]==2 and s["menuage"]>=360)
    snapshot("last-level-next-enabled")
    resets=state()["resets"]
    touch(*layout["gameui"]["anchors"][10]); touch(*layout["gameui"]["anchors"][10],False)
    frames=[]
    for _ in range(240):
        run(1); frames.append(framebuffer())
        if state()["popup"]==1 and state()["popupage"]>=65: break
    assert state()["view"]==6 and state()["popup"]==1 and state()["resets"]==resets,state()
    frames[0].save(directory/"finished-opening.gif",save_all=True,append_images=frames[1:],duration=17,loop=0)
    snapshot("finished-popup")
    tap(10,10)
    touch(128,96); touch(210,96); touch(210,96,False)
    run(60)
    assert state()["popup"]==1 and state()["pack"]==16 and state()["view"]==6
    # Hardware retains the last held coordinate on pen-up; drag out before lifting.
    touch(*layout["popup"]["positions"][2]); touch(10,10); touch(10,10,False)
    assert state()["popup"]==1
    tap(*layout["popup"]["positions"][2]); wait(lambda s:s["popup"]==0)
    snapshot("finished-dismissed")
    assert state()["view"]==6 and state()["pack"]==16 and state()["resets"]==resets
    key(0)
    assert state()["view"]==5
    report.update(passed=True,syntheticCompletion=True,finalLevel=425,modalInputCapture=True)
    (directory/"finishedreport.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
    print("PASS: synthetic Mechanical 17-25 completion, enabled Next, DX popup, modal touch capture, dismissal and home return")
