from PIL import Image, ImageDraw


def build(menu):
    quad = menu["quad"]
    for index in range(41):
        quad("body" + str(index), "char_animations", index, factor=1, restore=True, group="body" + str(index // 6))
    for index in range(13):
        quad("bodysad" + str(index), "char_animations3", index, factor=1, restore=True, group="bodysad" + str(index // 6))
    for index in range(2):
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
