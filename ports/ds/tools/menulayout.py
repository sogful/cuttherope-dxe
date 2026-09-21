"""Layout-only refresh; leaves every packed pixel and upper-screen asset intact."""
import hashlib
import json
import re
from pathlib import Path

import uiscale


def title(fit):
    factor=192/1440*fit*uiscale.title
    return [[round(128+(x-1280)*factor),round(64+(y-410)*factor)]
            for x,y in ((1280,410),(1423,685.5),(1603,729.5))]


def levels():
    return [[56+i%5*36,24+i//5*36] for i in range(25)]


def candyhit(fit):
    side=round(281*192/1440*fit*uiscale.title)
    return side,min(side,2*(125-title(fit)[1][1]))


def popup(paper,fit,frames):
    origin=[128,round(96-paper["oy"]-paper["h"]/2)]
    positions=[]
    for index,offset in ((2,-250),(3,-30),(4,0)):
        point=frames[index]["spriteSourceSize"]
        positions.append([round(origin[0]+(point["x"]-1280)*1.2*fit*192/1440),
                          round(origin[1]+((point["y"]-720)*1.2+offset)*fit*192/1440)])
    return origin,positions


def update(output):
    path=output/"menumanifest.json"
    before=path.read_bytes()
    manifest=json.loads(before)
    assert manifest["uiscale"]["title"]==uiscale.title and manifest["uiscale"]["popup"]==uiscale.popup, "Rebake resized artwork with --assets first"
    upperpath=output/"uppermanifest.json"
    dependencies=[output.parent/"tools"/name for name in ("upperart.py","upperhud.py","uppermotion.py")]
    dependencies += [output.parent/"assets/feedcandy.png",path]
    fresh=upperpath.exists() and all(item.stat().st_mtime<=upperpath.stat().st_mtime for item in dependencies)
    manifest["titlepositions"]=title(manifest["mainfit"])
    manifest["levelpositions"]=levels()
    for item in manifest["controls"]:
        if item["view"]=="home" and item["action"]=="skinmenu":
            item["x"],item["y"]=manifest["titlepositions"][1]
            item["w"],item["h"]=candyhit(manifest["mainfit"])
    paper=next(s for s in manifest["sprites"] if s["name"]=="popuppaper")
    frames=json.loads((output.parents[2]/"content/images/menu_popup.json").read_text())["frames"]
    origin,positions=popup(paper,manifest["fit"]*uiscale.popup,frames)
    manifest["popup"].update(origin=origin,positions=positions)
    after=json.dumps(manifest,indent=2,ensure_ascii=False).encode("utf-8")
    if before==after: return
    headerpath=output/"menuassets.hpp"
    header=headerpath.read_text()
    for name,values in (("titlepositions",manifest["titlepositions"]),("levelpositions",manifest["levelpositions"]),("popuppositions",positions)):
        body=",".join("{"+",".join(map(str,row))+"}" for row in values)
        header,count=re.subn(r"(inline constexpr int "+name+r"\[\d+\]\[2\] = )\{[^;]+\};",r"\g<1>{"+body+"};",header)
        assert count==1,name
    definition="inline constexpr int popuporigin[2] = {"+",".join(map(str,origin))+"};"
    if "inline constexpr int popuporigin" in header:
        header=re.sub(r"inline constexpr int popuporigin[^;]+;",definition,header)
    else: header=header.replace("inline constexpr int popuppositions",definition+"\ninline constexpr int popuppositions")
    candy=next(item for item in manifest["controls"] if item["view"]=="home" and item["action"]=="skinmenu")
    header,count=re.subn(r"(\{ui::view::home,ui::action::skinmenu,)\d+,\d+,\d+,\d+,",lambda m:m[1]+f"{candy['x']},{candy['y']},{candy['w']},{candy['h']},",header)
    assert count==1
    headerpath.write_text(header,encoding="utf-8")
    path.write_bytes(after)
    if fresh:
        upper=json.loads(upperpath.read_text())
        if upper["menuManifestSha256"]==hashlib.sha256(before).hexdigest():
            upper["menuManifestSha256"]=hashlib.sha256(after).hexdigest()
            upperpath.write_text(json.dumps(upper,indent=2),encoding="utf-8")
    print("Refreshed menu anchors/hitboxes; packed artwork unchanged",flush=True)


if __name__=="__main__":
    update(Path(__file__).resolve().parents[1]/"generated")
