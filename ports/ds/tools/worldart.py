from PIL import Image, ImageDraw
import xml.etree.ElementTree as xml
import math
from levels import boxes


def build(menu):
    quad = menu["quad"]
    for index in range(41):
        quad("body" + str(index), "char_animations", index, factor=1, restore=True, group="body" + str(index // 6))
    for index in range(13):
        quad("bodysad" + str(index), "char_animations3", index, factor=1, restore=True, group="bodysad" + str(index // 6))
    for index in range(boxes):
        quad("seat" + str(index), "char_supports", index, factor=1, restore=True, group="seat" + str(index))
    for index in range(30):
        quad("bubble" + str(index), "obj_bubble", index, factor=1, restore=True, group="bubble" + str(index // 6))
    for index in range(13):
        quad("spider" + str(index), "obj_spider", index, factor=1, restore=True, group="spider")
    for index in range(4):
        quad("pump" + str(index), "obj_pump", index, factor=1, restore=True, group="pump")
        quad("spike" + str(index), "obj_spikes", 8 + index, factor=1, group="spike" + str(index))
    for index in range(8):
        quad("tool" + str(index), "obj_spikes", index, factor=1, restore=True, group="tool" + str(index))
    for index in range(1,5):
        quad("bee" + str(index), "obj_bee", index, factor=.77, restore=True, group="bee", pivot=(143,196))
    quad("pollen", "obj_bee", 5, factor=1.5, group="pollen")
    for index in (19, 20):
        quad("timedstar" + str(index), "obj_star_idle", index, factor=1, group="timedstars")
    ring, _ = menu["assets"].readframe("obj_star_idle", 19)
    ring = ring.resize(tuple(round(v * menu["scale"]) for v in ring.size), Image.Resampling.LANCZOS)
    for phase in range(1, 33):
        mask = Image.new("L", ring.size)
        ImageDraw.Draw(mask).pieslice((0, 0, ring.width - 1, ring.height - 1), -90, -90 + phase * 360 / 32, fill=255)
        canvas = Image.new("RGBA", ring.size)
        canvas.paste(ring, (0, 0), mask)
        menu["add"]("ring" + str(phase), canvas, "timer" + str((phase - 1) // 8))
    for index in range(2):
        quad("fabriccover" + str(index), "bgr_02_cover", index, factor=1, group="fabriccover" + str(index))
    for box in range(3, boxes + 1):
        for index in range(2):
            name = "boxcover" + str(box) + "x" + str(index)
            quad(name, f"bgr_{box:02}_cover", index, factor=1, group=name)
    for index in range(5):
        quad("electro" + str(index), "obj_electrodes", index, factor=1, restore=True, group="electro")
    for index in range(5):
        quad("hat" + str(index), "obj_hat", index, factor=.7, restore=True, group="hat",
             pivot=(215, 84.5 if index < 2 else 245.5))
    for index in range(5):
        quad("rail" + str(index), "obj_hook", 6 + index, factor=1, group="rail")
    for index in range(5):
        quad("merge" + str(index), "candies/obj_candy_fx", 11 + index, factor=1, restore=True, group="merge")
    for index in range(10):
        quad("bouncer" + str(index), "obj_bouncer", index, factor=1, group="bouncer" + str(index // 5))
    for index in range(13):
        quad("starburst" + str(index), "obj_star_disappear", index, factor=1, restore=True, group="starburst" + str(index // 5))
    for index in range(4):
        quad("wheel" + str(index), "obj_hook", 11 + index, factor=1, group="wheel")
    for index in range(3):
        quad("gravity" + str(index), "obj_star_idle", 21 + index, factor=1, group="gravity" + str(index))
    # Rasterize HorizontallyTiledImage at source resolution, then downsample once.
    # This retains the native 44-pixel repeat and clipped final tile at DS scale.
    lengths, radii = set(), set()
    for box in range(1, boxes + 1):
        for level in range(1, 26):
            for node in xml.parse(menu["content"] / f"maps/{box}_{level}.xml").iter():
                if node.tag not in ("grab", "ghost"): continue
                length = float(node.get("moveLength", 0)) * 3
                if length > 0: lengths.add(int(length))
                radius = float(node.get("radius", -1)) * 3
                if radius >= 0: radii.add(int(radius))
    circles = []
    for radius in sorted(radii):
        # DX uses alternating circle chords with a 4-world-pixel solid core
        # and one-pixel alpha fringe on each edge. Integrate at 8x DS size.
        size = math.ceil((radius + 4) * menu["scale"]) * 2 + 1
        count = max(16, radius) // 2
        count += count % 2
        vertices = [(math.cos(i * math.tau / count) * radius, math.sin(i * math.tau / count) * radius) for i in range(count)]
        high = Image.new("RGBA", (size * 8, size * 8), (51,128,230,0))
        pixels = high.load()
        ratio = menu["scale"] * 8
        for edge in range(0,count,2):
            ax, ay = vertices[edge]; bx, by = vertices[edge+1]
            vx, vy = bx-ax, by-ay; length = math.hypot(vx,vy)
            for y in range(max(0,int((min(ay,by)-4)*ratio+size*4)), min(size*8,math.ceil((max(ay,by)+4)*ratio+size*4))):
                for x in range(max(0,int((min(ax,bx)-4)*ratio+size*4)), min(size*8,math.ceil((max(ax,bx)+4)*ratio+size*4))):
                    px,py = (x+.5-size*4)/ratio-ax,(y+.5-size*4)/ratio-ay
                    t = (px*vx+py*vy)/(length*length)
                    if not 0 <= t <= 1: continue
                    distance = abs(px*vy-py*vx)/length
                    alpha = round(max(0,min(1,3-distance))*255)
                    if alpha > pixels[x,y][3]: pixels[x,y] = (51,128,230,alpha)
        canvas = high.resize((size,size),Image.Resampling.LANCZOS)
        name = "catch" + str(radius)
        menu["add"](name,canvas,name,source={"catchRadius":radius})
        circles.append((radius,name))
    left, center, right = (menu["assets"].readframe("obj_hook", q)[0] for q in (6,8,7))
    tracks = []
    for length in sorted(lengths):
        width, height = length + 142, max(left.height,center.height,right.height)
        canvas = Image.new("RGBA", (width,height))
        canvas.paste(left,(0,(height-left.height)//2))
        cursor = left.width
        while cursor < width - right.width:
            part = center.crop((0,0,min(center.width,width-right.width-cursor),center.height))
            canvas.paste(part,(cursor,(height-center.height)//2))
            cursor += part.width
        canvas.paste(right,(width-right.width,(height-right.height)//2))
        canvas = canvas.resize(tuple(round(v * menu["scale"]) for v in canvas.size),Image.Resampling.LANCZOS)
        name = "track" + str(length)
        menu["add"](name,canvas,"rails"+str(length),source={"railLength":length})
        tracks.append((length,name))
    return tracks, circles


def header(groups, ids):
    output = ["struct rail { int length, sprite; };"]
    for name, rows in zip(("rails", "circles"), groups):
        output += ["inline constexpr rail " + name + "[] = {"] + [f"{{{length},{ids[sprite]}}}," for length,sprite in rows] + ["};"]
    return output
