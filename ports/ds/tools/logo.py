"""Put the static upper image in 48 KiB of H/I, freeing C for frame capture."""

import json
from pathlib import Path
import struct
from PIL import Image, ImageChops, ImageOps, ImageStat

root = Path(__file__).resolve().parents[1]


def build(output):
    source = ImageOps.contain(Image.open(root / "assets/logods.png").convert("RGBA"),
                              (256, 192), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", (256, 192))
    canvas.paste(source, ((256 - source.width) // 2, (192 - source.height) // 2), source)
    indexed = canvas.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    colors = indexed.getpalette()
    palette = [(colors[i] >> 3) | ((colors[i + 1] >> 3) << 5) | ((colors[i + 2] >> 3) << 10)
               for i in range(0, 768, 3)]
    (output / "logo.bin").write_bytes(indexed.tobytes())
    (output / "logopalette.bin").write_bytes(struct.pack("<256H", *palette))
    indexed.putpalette([((color >> shift) & 31) * 255 // 31 for color in palette for shift in (0, 5, 10)])
    preview = indexed.convert("RGB")
    preview.save(output / "logo.png")
    difference = ImageStat.Stat(ImageChops.difference(canvas, preview))
    quality = {"meanChannelError": difference.mean, "rmsChannelError": difference.rms}
    assert max(difference.mean) < 5, quality
    (output / "logotest.json").write_text(json.dumps(quality, indent=2), encoding="utf-8")
    (output / "logo.hpp").write_text('#pragma once\nextern "C" { extern const unsigned char logopalettedata[]; }\n', encoding="utf-8")
    (output / "logo.s").write_text('.section .rodata\n.balign 4\n.global logopalettedata\nlogopalettedata:\n.incbin "generated/logopalette.bin"\n', encoding="utf-8")
    manifest = output / "manifest.json"
    if manifest.exists():
        data = json.loads(manifest.read_text())
        data["upperbytes"] = 49152
        data["upperpalettebytes"] = 512
        manifest.write_text(json.dumps(data, indent=2), encoding="utf-8")


if __name__ == "__main__":
    build(root / "generated")
