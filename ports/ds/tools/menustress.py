"""Reproduce rapid credits/options/carousel exits without settling every input."""
import json


def check(run,tap,key,telemetry,settle,snapshot,control,pointer,buttons,report,directory):
    def rawtap(x,y,delay):
        pointer[:]=[round(x/255*65534-32767),round((192+y)/383*65534-32767),1]
        run(2)
        pointer[2]=0
        run(2+delay)

    def cancel(delay):
        buttons.add(0)
        run(2)
        buttons.discard(0)
        run(2+delay)

    def home():
        pointer[2]=0
        buttons.clear()
        settle()
        for _ in range(5):
            if telemetry()["view"]==5: return
            key(0)
            settle()
        raise AssertionError("Could not return to title: "+repr(telemetry()))

    cases=[]
    for delay in (0,1,4,12,24):
        for repeat in range(2):
            home()
            tap(*control("home","options"))
            tap(*control("options","credits"))
            assert telemetry()["view"]==9
            for _ in range(4): cancel(delay)
            home()
            tap(*control("home","packs"))
            assert telemetry()["view"]==6
            for _ in range(4):
                cancel(delay)
                rawtap(*control("home","packs"),delay)
            home()
            state=snapshot(f"delay-{delay}-repeat-{repeat}")
            assert state["view"]==5 and not state["renderfault"] and not state["upperfault"]
            cases.append(dict(delay=delay,repeat=repeat,frames=state["frames"]))
    report.update(passed=True,rapidMenuCases=cases)
    (directory/"menustress.json").write_text(json.dumps(report,indent=2))
    print(f"PASS: {len(cases)} rapid credits/options/carousel exit sequences and title recoveries")
