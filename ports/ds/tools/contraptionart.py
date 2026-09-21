"""RotatedCircle/Ghost source quads and supersampled DX circle geometry."""
import math
import xml.etree.ElementTree as xml
from PIL import Image, ImageDraw


def build(menu):
    quad, add, scale = menu["quad"], menu["add"], menu["scale"]
    for i in range(29):
        quad("mouse"+str(i),"obj_mouse",i,factor=1,restore=True,group="mouse"+str(i//8))
    for i in range(43):
        quad("lighter"+str(i),"obj_lighter",i,factor=1,restore=i in (1,2),group="lightglow" if i==0 else "lighter"+str(i//8))
    for i in range(31):
        quad("nightstar"+str(i),"obj_star_night",i,factor=1,group="nightstar"+str(i//8))
    for i in range(7):
        quad("sleep"+str(i),"char_animations_sleeping",i,factor=1,restore=True,group="sleep")
    quad("zzz","fx_sleep",0,factor=1,group="zzz")
    for i in range(35):
        quad("pipe"+str(i),"obj_pipe",i,factor=1,restore=i>=2,group="pipebody" if i<2 else "steampuffs")
    for i in range(3):
        quad("lantern"+str(i),"obj_lantern",i,factor=1,restore=True,group="lantern")
    for i in range(52):
        resource = "obj_lantern" if i<3 else "candies/obj_candy_"+str(i+1).zfill(2)
        quad("lanterncandy"+str(i),resource,3+i if i<3 else 10,factor=1,restore=True,group="lanterncandy"+str(i))
    for i in range(7):
        quad("ghost"+str(i),"obj_ghost",i,factor=1,group="ghost")
    for i in (4,5):
        quad("ghosthook"+str(i-4),"obj_hook",i,factor=1,group="ghosthook")
    for i in (3,4,5):
        quad("vinyl"+str(i),"obj_vinil",i,factor=1,group="vinylhandles")
    half, _ = menu["assets"].readframe("obj_vinil",2)
    sticker = Image.new("RGBA",(290,288))
    sticker.alpha_composite(half,(0,0))
    sticker.alpha_composite(half.transpose(Image.Transpose.FLIP_LEFT_RIGHT),(143,0))
    add("vinyllabel",sticker.resize((round(290*scale),round(288*scale)),Image.Resampling.LANCZOS),"vinyllabel")
    sizes = set()
    maps = []
    for level in range(1,26):
        discs = list(xml.parse(menu["content"] / f"maps/11_{level}.xml").iter("rotatedCircle"))
        maps.append(discs)
        sizes.update(int(d.get("size")) for d in discs)
    for box in range(13,menu["boxes"]+1):
        for level in range(1,26):
            sizes.update(int(d.get("size")) for d in xml.parse(menu["content"] / f"maps/{box}_{level}.xml").iter("rotatedCircle"))
    vinyls, contours = [], []
    for size in sorted(sizes):
        base, control = size / 167, max(size / 167,.75)
        face, highlight, ring = (name+str(size) for name in ("vinylface","vinylshine","vinylring"))
        quad(face,"obj_vinil",0,factor=base,group=face)
        quad(highlight,"obj_vinil",1,factor=base,group=highlight)
        radius, width = 534*base+9*control, 12*control
        extent = math.ceil((radius+5)*scale)+1
        high = Image.new("RGBA",(extent*16,extent*16))
        pix = high.load()
        for y in range(high.height):
            for x in range(high.width):
                distance = math.hypot((x+.5)/8-extent,(y+.5)/8-extent)/scale
                edge = abs(distance-(radius-width/2))-width/2
                alpha = round(max(0,min(1,1-edge/5))*255)
                if alpha: pix[x,y] = (255,255,255,alpha)
        add(ring,high.resize((extent*2,extent*2),Image.Resampling.LANCZOS),ring)
        vinyls.append((size,face,highlight,ring))
    for level,discs in enumerate(maps):
        for i,a in enumerate(discs):
            for j,b in enumerate(discs):
                if i==j: continue
                x,y = (float(b.get(k))*3-float(a.get(k))*3 for k in ("x","y"))
                radius,other = (534*int(d.get("size"))/167 for d in (a,b))
                distance = math.hypot(x,y)
                if not distance or distance>=radius+other or radius>=distance+other: continue
                intersection = (radius*radius-other*other+distance*distance)/(2*distance)
                offset = math.acos(max(-1,min(1,(distance-intersection)/other)))
                angle = math.atan2(-y,-x)
                width = 21*(int(b.get("size"))/167)*.5
                points = [(x+math.cos(angle-offset+n*offset*2/80)*(other-width*.5),y+math.sin(angle-offset+n*offset*2/80)*(other-width*.5)) for n in range(81)]
                left,top = (math.floor((min(p[k] for p in points)-width)*scale) for k in (0,1))
                right,bottom = (math.ceil((max(p[k] for p in points)+width)*scale) for k in (0,1))
                high = Image.new("RGBA",(max(1,right-left)*8,max(1,bottom-top)*8))
                draw = ImageDraw.Draw(high)
                draw.line([((px*scale-left)*8,(py*scale-top)*8) for px,py in points],fill=(255,255,255,51),width=max(1,round(width*scale*8)),joint="curve")
                name = f"vinylcontour{level}x{i}x{j}"
                add(name,high.resize((high.width//8,high.height//8),Image.Resampling.LANCZOS),name,origin=(-left,-top))
                contours.append((level,i,j,name))
    return vinyls,contours


def header(groups,ids):
    vinyls,contours = groups
    out = ["struct vinyl { int size, face, shine, ring; };", "inline constexpr vinyl vinyls[] = {"]
    out += [f"{{{size},{ids[face]},{ids[shine]},{ids[ring]}}}," for size,face,shine,ring in vinyls]
    out += ["};", "struct contour { int level, front, back, sprite; };", "inline constexpr contour contours[] = {"]
    out += [f"{{{level},{a},{b},{ids[name]}}}," for level,a,b,name in contours]
    return out+["};"]
