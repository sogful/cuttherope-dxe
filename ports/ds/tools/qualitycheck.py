"""Nearest-pixel comparison of the actual DS texture format and source artwork."""
import argparse
import json
import struct
from pathlib import Path
from PIL import Image
from uppermotion import unpack

root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument("--before",action="store_true")
args=parser.parse_args()
manifest=json.loads((root/"generated/menumanifest.json").read_text(encoding="utf-8"))
sprites={item["name"]:item for item in manifest["sprites"]}
out=root/"build/qualitybaseline"
out.mkdir(exist_ok=True)
canvas=Image.new("RGB",(7*132,128),(130,112,84))
for index in range(7):
    item=sprites["belt"+str(index)]; page=manifest["pages"][item["page"]]
    prefix=root/"generated"/page["name"]
    palette=struct.unpack("<32H",prefix.with_name(prefix.name+"palette.bin").read_bytes())
    data=unpack(prefix.with_suffix(".lz").read_bytes())
    decoded=Image.new("RGBA",(page["width"],page["height"]))
    decoded.putdata([tuple(((palette[pixel&31]>>shift)&31)*255//31 for shift in (0,5,10))+(round((pixel>>5)*255/7),) for pixel in data])
    box=(item["x"],item["y"],item["x"]+item["w"],item["y"]+item["h"])
    original=Image.open(prefix.with_suffix(".png")).convert("RGBA").crop(box)
    actual=decoded.crop(box)
    for row,image in enumerate((original,actual)):
        image=image.resize((image.width*4,image.height*4),Image.Resampling.NEAREST)
        canvas.paste(image,(index*132,row*64),image)
    print(item["name"],original.size,"dither",page["dither"])
canvas.save(out/("conveyor-before.png" if args.before else "conveyor-after.png"))
for name in ("pauseplate","skin0"):
    print(name,{key:sprites[name][key] for key in ("w","h","ox","oy")})
