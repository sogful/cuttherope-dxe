"""Bake scene palettes and scrolling backgrounds for the secondary 2D display."""

import hashlib
import json
from pathlib import Path
import struct

import numpy as np
from PIL import Image

root = Path(__file__).resolve().parents[1]
output = root / "generated"


def dim(image, strength):
    data = np.asarray(image.convert("RGB"), dtype=np.uint16)
    return Image.fromarray((data*strength//31).astype(np.uint8))


def palette(images):
    samples = np.concatenate([np.asarray(image.convert("RGB")).reshape(-1, 3)[::4] for image in images])
    training = Image.fromarray(samples.reshape(1, len(samples), 3))
    quantized = training.quantize(colors=240, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    colors = np.asarray(quantized.getpalette()[:720], dtype=np.uint16).reshape(240, 3)*31//255
    fixed = np.array([(0,0,0),(31,31,31),(31,31,0),(31,27,0),(31,20,0),(31,12,0),(31,4,0),(31,0,0),
                      (3,3,3),(7,7,7),(11,11,11),(15,15,15),(19,19,19),(23,23,23),(27,27,27),(29,29,29)], dtype=np.uint16)
    colors = np.concatenate((colors, fixed))
    packed = colors[:, 0] | (colors[:, 1] << 5) | (colors[:, 2] << 10)
    values = np.arange(32768, dtype=np.uint16)
    rgb = np.stack([((values >> shift) & 31) for shift in (0,5,10)], axis=1).astype(np.int32)
    lookup = np.empty(32768, dtype=np.uint8)
    for start in range(0,32768,512):
        delta = rgb[start:start+512, None, :] - colors.astype(np.int32)[None, :, :]
        error = (delta*delta*np.array([2,3,2])).sum(axis=2)
        lookup[start:start+512] = error.argmin(axis=1)
    return packed, lookup


def indexed(image, lookup):
    data = np.asarray(image.convert("RGB"), dtype=np.uint16)
    threshold = np.asarray(((0,8,2,10),(12,4,14,6),(3,11,1,9),(15,7,13,5)),dtype=np.int16)
    offset = np.tile(threshold,(image.height//4+1,image.width//4+1))[:image.height,:image.width]-8
    data = np.clip(data.astype(np.int16)+offset[:,:,None]//3,0,255).astype(np.uint16)*31//255
    return lookup[data[:,:,0] | (data[:,:,1]<<5) | (data[:,:,2]<<10)].tobytes()


def main():
    import upperhud
    import uppermotion
    hudimages,hudrecords=upperhud.build()
    manifest = json.loads((output / "menumanifest.json").read_text(encoding="utf-8"))
    sprites = {item["name"]:item for item in manifest["sprites"]}
    def sprite(name):
        item = sprites[name]
        page = manifest["pages"][item["page"]]
        return Image.open(output / (page["name"]+".png")).convert("RGBA").crop(
            (item["x"],item["y"],item["x"]+item["w"],item["y"]+item["h"]))
    photo = Image.open(root / "assets/feedcandy.png").convert("RGBA")
    menus = [sprite(name) for name in ("titleback","menuback","skinback")]
    covers = [sprite("levelback"+str(box)) for box in range(17)]
    worlds = [[Image.open(output/f"background{box+1}x{section}.png").convert("RGB") for section in range(1,4)] for box in range(17)]
    worldcolors = []
    for page in manifest["pages"]:
        if page["direct"] or page.get("group","").startswith(("text","packtext","credits")):
            continue
        values = np.frombuffer((output/(page["name"]+"palette.bin")).read_bytes(), dtype="<u2")
        worldcolors.extend(tuple(int((value>>shift)&31)*255//31 for shift in (0,5,10)) for value in values)
    colorimage = Image.new("RGB", (len(worldcolors),1))
    colorimage.putdata(worldcolors)
    colorimage = dim(colorimage,17)
    samples = [[image,dim(image,24),dim(image,17),photo,photo] for image in menus]
    samples += [[dim(image,17) for image in group]+[cover,dim(cover,24),photo,colorimage]
                for group,cover in zip(worlds,covers)]
    for sample in samples: sample.extend(hudimages)
    palettes, lookups = [], []
    for index, images in enumerate(samples):
        colors, lookup = palette(images)
        palettes.append(colors); lookups.append(lookup)
        print("Upper palette", index+1, "/", len(samples), flush=True)
    palettebytes = b"".join(colors.astype("<u2").tobytes()+lookup.tobytes() for colors,lookup in zip(palettes,lookups))
    (output/"nitro/upperpal.bin").write_bytes(palettebytes)
    hudbytes=b"".join(upperhud.encode(hudimages,lookup) for lookup in lookups)
    (output/"nitro/upperhud.bin").write_bytes(hudbytes)
    preview=Image.new("RGBA",(256,96))
    for index in range(3): preview.alpha_composite(hudimages[(0,5,10)[index]],(index*80+15,0))
    left=4
    for image in hudimages[11:]: preview.alpha_composite(image,(left,58)); left+=image.width+3
    preview.save(output/"upperhud.png")
    backgrounds, records = bytearray(), []
    def background(image, profile, photograph=False):
        item = (len(backgrounds),image.height,profile)
        pixels = np.frombuffer(indexed(image,lookups[profile]),dtype=np.uint8).reshape(image.height,256).copy()
        if photograph:
            source=np.asarray(photo,dtype=np.uint16)
            rgb=source[:,:,:3]*31//255
            indices=lookups[profile][rgb[:,:,0] | (rgb[:,:,1]<<5) | (rgb[:,:,2]<<10)]
            left,top=128-photo.width//2,96-photo.height//2
            target=pixels[top:top+photo.height,left:left+photo.width]
            target[source[:,:,3]>0]=indices[source[:,:,3]>0]
        backgrounds.extend(pixels.tobytes())
        records.append(item)
        return len(records)-1
    mainmenus = [background(image,profile,True) for profile,image in enumerate(menus)]
    levelmenus = [background(image,3+box,True) for box,image in enumerate(covers)]
    gamebacks = []
    for box,group in enumerate(worlds):
        row = []
        for image in group:
            extended = Image.new("RGB",(256,image.height+192))
            # Off-map space uses the authored interior of the tall-box composite.
            extended.paste(worlds[box][2].crop((0,192,256,384)),(0,0))
            extended.paste(image,(0,192))
            row.append(background(dim(extended,17),3+box))
        gamebacks.append(row)
    (output/"nitro/upperbg.bin").write_bytes(backgrounds)
    pixels = np.asarray(photo,dtype=np.uint16)
    rgb = pixels[:,:,:3]*31//255
    packed = rgb[:,:,0] | (rgb[:,:,1]<<5) | (rgb[:,:,2]<<10) | ((pixels[:,:,3]>0).astype(np.uint16)<<15)
    (output/"nitro/upperphoto.bin").write_bytes(packed.astype("<u2").tobytes())
    spans=[]
    mask=np.asarray(photo)[:,:,3]>0
    for y in range(192):
        row=y-(96-photo.height//2)
        columns=np.flatnonzero(mask[row]) if 0<=row<photo.height else []
        spans.append((128-photo.width//2+int(columns[0]),128-photo.width//2+int(columns[-1])+1) if len(columns) else (0,0))
    motion=uppermotion.bake(output,manifest,backgrounds,records,palettes,lookups,spans)
    header = ["#pragma once", "namespace upperart {", "struct background { unsigned offset; int height, palette; };",
        "inline constexpr background backgrounds[] = {"+",".join("{"+",".join(map(str,item))+"}" for item in records)+"};",
        "inline constexpr int menus[] = {"+",".join(map(str,mainmenus))+"};",
        "inline constexpr int levels[] = {"+",".join(map(str,levelmenus))+"};",
        "inline constexpr int worlds[17][3] = {"+",".join("{"+",".join(map(str,row))+"}" for row in gamebacks)+"};",
        f"inline constexpr int photowidth = {photo.width}, photoheight = {photo.height};",
        "inline constexpr unsigned char photospans[192][2] = {"+",".join("{"+",".join(map(str,row))+"}" for row in spans)+"};",
        f"inline constexpr unsigned hudbytes = {len(hudbytes)//len(lookups)};",
        "struct glyph { unsigned offset; int width,height,ox,oy,advance; };",
        "inline constexpr glyph hud[] = {"+",".join("{"+",".join(map(str,row))+"}" for row in hudrecords)+"};",
        "inline constexpr int motion[] = {"+",".join(map(str,motion))+"};",
        f"inline constexpr int motionsteps={uppermotion.steps}, motioninterval={uppermotion.interval}, motionkey={uppermotion.keyinterval};", "}"]
    (output/"upperassets.hpp").write_text("\n".join(header)+"\n")
    (output/"uppermanifest.json").write_text(json.dumps(dict(palettes=len(palettes), backgrounds=records,
        photoSize=list(photo.size), menuManifestSha256=hashlib.sha256((output/"menumanifest.json").read_bytes()).hexdigest(),
        photoSha256=hashlib.sha256((root/"assets/feedcandy.png").read_bytes()).hexdigest(),
        dim=17/31, paletteBytes=len(palettebytes), backgroundBytes=len(backgrounds),hudRecords=hudrecords,
        hudBytes=len(hudbytes),motionOffsets=motion,motionBytes=(output/"nitro/uppermotion.bin").stat().st_size),indent=2))


if __name__ == "__main__":
    main()
