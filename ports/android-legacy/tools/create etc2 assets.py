import etcpak, numpy as np, struct, os, glob
from PIL import Image

# keep very scaled textures because they'll look terrible compressed. sometimes this doesn't help though
LOSSLESS = {"CutTheRopeDXLogo", "SubprojectLogo", "menu_bgr", "menu_bgr_shadow"}

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "images")
pngs = glob.glob(os.path.join(ROOT, "**", "*.png"), recursive=True)
total_png = total_out = count = 0
for p in pngs:
    total_png += os.path.getsize(p)
    im = Image.open(p).convert("RGBA")
    w, h = im.size
    lossless = os.path.splitext(os.path.basename(p))[0] in LOSSLESS
    if not lossless:
        pw, ph = (w + 3) // 4 * 4, (h + 3) // 4 * 4
        if (pw, ph) != (w, h):
            padded = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
            padded.paste(im, (0, 0))
            im, w, h = padded, pw, ph
    arr = np.asarray(im).astype(np.uint16)
    a = arr[:, :, 3:4]
    arr[:, :, 0:3] = (arr[:, :, 0:3] * a + 127) // 255
    pm = arr.astype(np.uint8).tobytes()
    if lossless:
        magic, data = b"RAW0", pm
    else:
        magic, data = b"ETC2", etcpak.compress_to_etc2_rgba(pm, w, h)
    with open(os.path.splitext(p)[0] + ".etc2", "wb") as f:
        f.write(magic)
        f.write(struct.pack("<ii", w, h))
        f.write(data)
    total_out += len(data) + 12
    count += 1

print(f"encoded {count} textures: {total_png/1048576:.1f} MB png -> {total_out/1048576:.1f} MB etc2/raw")
