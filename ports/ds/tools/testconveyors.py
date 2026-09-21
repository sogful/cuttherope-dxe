"""Compare conveyor bodies, items, scales and ownership against original C# traces."""
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess

root=Path(__file__).resolve().parents[1]
binary=root/"build/conveyortest.exe"
subprocess.run([shutil.which("g++"),"-std=c++17","-O2","-Wall","-Wextra","-Werror","-msse2","-mfpmath=sse","-ffp-contract=off",
    "-I"+str(root/"include"),"-I"+str(root/"generated"),
    *(str(root/"source"/name) for name in ("simulation.cpp","mechanics.cpp","advanced.cpp","contraptions.cpp","devices.cpp","nocturnal.cpp","conveyors.cpp","levelstore.cpp")),
    str(root/"tests/conveyors.cpp"),"-o",str(binary)],check=True)
subprocess.run([str(binary)],check=True)
array=lambda s: json.loads(s.replace("{","[").replace("}","]"))
kinds={name:i for i,name in enumerate(("bubble","star","bouncer","hat","steam","pump","hook"))}
runs,failures,hashes=[],[],{}
for fixture in sorted((root.parent/"roblox/tests").glob("MechanicalGoldenData[0-9]*.luau")):
    hashes[fixture.name]=hashlib.sha256(fixture.read_bytes()).hexdigest()
    data=fixture.read_text().split("return ",1)[1].strip()
    match=re.fullmatch(r'\{level=(\d+),mode=(\d+),items=(.*?),belts=(.*?),actions=(.*?),samples=(.*)\}',data)
    assert match,fixture
    level,mode,items,belts,actions,samples=match.groups()
    items,belts,actions,samples=map(array,(items,belts,actions,samples))
    initial=[(item[1]-1,*samples[0][3][i][:2]) for i,item in enumerate(items) if item[0]=="star"]
    commands=str(len(initial))+"\n"+"".join(" ".join(map(str,row))+"\n" for row in initial)
    commands+="".join(f"{a[0]} {dict(down=0,drag=1,up=2,cut=3,removeStar=4)[a[1]]} {a[2]-1} {a[3]} {a[4]}\n" for a in actions)
    rows={r["tick"]:r for r in map(json.loads,subprocess.check_output([str(binary),level,str(samples[-1][0])],input=commands,text=True).splitlines())}
    worst=dict(candy=0,previous=0,hook=0,item=0,position=0,scale=0)
    runfailures=[]
    # C# enumerates manuals before automatics. Resolve physical belt IDs below.
    import xml.etree.ElementTree as xml
    document=xml.parse(root.parents[1]/f"content/maps/17_{level}.xml")
    width=float(document.find("./layer[@name='settings']/map").get("width"))*3
    definitions=list(document.iter("transporter"))
    beltmap={i+1:next(j+1 for j,p in enumerate(belts) if abs(p[0]-(float(b.get("x"))*3+(2560-width)/2))<.01 and abs(p[1]-float(b.get("y"))*3)<.01) for i,b in enumerate(definitions)}
    for tick,bodies,hooks,expecteditems in samples:
        row=rows[tick]
        def fail(*detail):
            if len(runfailures)<5: runfailures.append((int(level),int(mode),tick,*detail))
        if len(bodies)!=len(row["bodies"]): fail("body count")
        for a,b in zip(bodies,row["bodies"]):
            for name,offset in (("candy",0),("previous",2)):
                error=math.hypot(a[offset]-b[offset],a[offset+1]-b[offset+1]); worst[name]=max(worst[name],error)
                if error>=.1: fail(name,error,a,b)
            if a[4]!=b[4]: fail("bubble",a,b)
        for a,b in zip(hooks,row["hooks"]):
            error=math.hypot(a[0]-b[0],a[1]-b[1]); worst["hook"]=max(worst["hook"],error)
            if error>=.1 or a[2]!=b[2]: fail("hook",error,a,b)
        actual={(a[0],a[1]):a[2:] for a in row["items"]}
        for ident,a in zip(items,expecteditems):
            b=actual[(kinds[ident[0]],ident[1]-1)]
            errors=dict(item=math.hypot(a[0]-b[0],a[1]-b[1]),position=abs(a[2]-b[2]),scale=abs(a[3]-b[3]))
            for name,error in errors.items():
                worst[name]=max(worst[name],error)
                if error>=(.001 if name=="scale" else .1): fail(name,ident,error,a,b)
            if a[4]!=beltmap.get(b[4],0): fail("ownership",ident,a,b)
    runs.append(dict(level=int(level),mode=int(mode),errors=worst,wraps=row["wraps"],handoffs=row["handoffs"]))
    failures.extend(runfailures)
report=dict(passed=not failures,runs=runs,failures=failures,sources=hashes,
    starCollection="Replayed C# removal actions: its export omits Draw and leaves star collision rectangles stale. Live moving-star pickup is tested separately.")
(root/"build/conveyortest.json").write_text(json.dumps(report,indent=2))
assert len(runs)==75,len(runs)
assert not failures,(len(failures),failures[:5])
print("PASS: 75 original C# Mechanical traces; maximum errors",{key:max(r["errors"][key] for r in runs) for key in worst})
