"""Serial, windowless measurements of emulated DS work and host throughput."""
import json
import statistics
import time


def check(run,tap,key,state,settle,snapshot,report,directory):
    results=[]
    def wait(predicate):
        for _ in range(1800):
            if predicate(state()): return
            run(1)
        raise AssertionError(state())
    def measure(name):
        settle(); run(120)
        first=state(); previous=first["frames"]; samples=[]
        start=time.perf_counter()
        for _ in range(360):
            run(1); current=state()
            if current["frames"]!=previous: samples.append(current["micros"])
            previous=current["frames"]
        seconds=time.perf_counter()-start
        item=dict(scene=name,updates=state()["frames"]-first["frames"],vblanks=360,
            updatesPerSecond=(state()["frames"]-first["frames"])*59.8261/360,
            hostFramesPerSecond=360/seconds,medianUs=statistics.median(samples),
            p95Us=sorted(samples)[int(len(samples)*.95)],seconds=seconds)
        results.append(item); print("BENCH:",json.dumps(item),flush=True)
        (directory/"benchmark.json").write_text(json.dumps(results,indent=2))
        snapshot("bench-"+name)
    measure("title")
    tap(128,170); measure("settings")
    tap(131,185); assert state()["unlocked"]
    key(0); tap(147,91); measure("customization")
    key(0); key(8); measure("boxes")
    key(8); key(8); settle(); wait(lambda s:s["ticks"]>=150)
    measure("cardboard-1")
    key(3); measure("pause")
    key(7); key(7); key(8); settle()
    assert state()["view"]==4
    tap(190,96); settle(); wait(lambda s:not s["intro"])
    measure("cardboard-15")
    key(3); key(7); key(7); key(8); settle(); key(0)
    for _ in range(16): key(7)
    run(120); tap(128,96); wait(lambda s:s["view"]==4); settle(); run(90)
    tap(128,166); wait(lambda s:s["view"]==0); settle(); wait(lambda s:not s["intro"])
    assert state()["level"]==422,state()
    measure("mechanical-23")
    report.update(passed=True,benchmark=results)
    (directory/"benchmark.json").write_text(json.dumps(report,indent=2))
    print("PASS: serial benchmark",flush=True)
