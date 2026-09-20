from PIL import Image, ImageDraw
import xml.etree.ElementTree as xml


def build(menu):
    quad = menu["quad"]
    for index in range(41):
        quad("body" + str(index), "char_animations", index, factor=1, restore=True, group="body" + str(index // 6))
    for index in range(13):
        quad("bodysad" + str(index), "char_animations3", index, factor=1, restore=True, group="bodysad" + str(index // 6))
    for index in range(6):
        quad("seat" + str(index), "char_supports", index, factor=1, restore=True, group="seat" + str(index))
    for index in range(30):
        quad("bubble" + str(index), "obj_bubble", index, factor=1, restore=True, group="bubble" + str(index // 6))
    for index in range(11):
        quad("spider" + str(index), "obj_spider", index, factor=1, restore=True, group="spider")
    for index in range(4):
        quad("pump" + str(index), "obj_pump", index, factor=1, restore=True, group="pump")
        quad("spike" + str(index), "obj_spikes", 8 + index, factor=1, group="spike" + str(index))
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
    for box in range(3, 7):
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
    # Rasterize HorizontallyTiledImage at source resolution, then downsample once.
    # This retains the native 44-pixel repeat and clipped final tile at DS scale.
    lengths = set()
    for box in range(1, 7):
        for level in range(1, 26):
            for node in xml.parse(menu["content"] / f"maps/{box}_{level}.xml").iter("grab"):
                length = float(node.get("moveLength", 0)) * 3
                if length > 0: lengths.add(int(length))
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
        menu["add"](name,canvas,"rails",source={"railLength":length})
        tracks.append((length,name))
    return tracks


def header(tracks, ids):
    return ["struct rail { int length, sprite; };", "inline constexpr rail rails[] = {"] + [f"{{{length},{ids[name]}}}," for length,name in tracks] + ["};"]
