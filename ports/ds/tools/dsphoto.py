"""Extract the original DS menu artwork from a user-supplied local dump."""

import argparse
import hashlib
import json
from pathlib import Path
import struct

import numpy as np
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]


def files(data):
    nameoffset, namesize, fatoffset, fatsize = struct.unpack_from("<4I", data, 0x40)
    assert nameoffset + namesize <= len(data) and fatoffset + fatsize <= len(data)
    names = data[nameoffset:nameoffset + namesize]
    result = {}

    def folder(index, prefix):
        offset, ident, _ = struct.unpack_from("<IHH", names, index * 8)
        while names[offset]:
            length = names[offset]
            offset += 1
            name = names[offset:offset + (length & 127)].decode("ascii")
            offset += length & 127
            if length & 128:
                child = struct.unpack_from("<H", names, offset)[0]
                offset += 2
                folder(child & 4095, prefix + name + "/")
            else:
                start, end = struct.unpack_from("<II", data, fatoffset + ident * 8)
                assert 0 <= start <= end <= len(data)
                result[prefix + name] = (start, data[start:end])
                ident += 1
    folder(0, "")
    return result


def names(data):
    version, count = struct.unpack_from("<II", data)
    assert version == 0 and 0 < count < 256
    cursor, names = 8, []
    for _ in range(count):
        length = data[cursor]
        cursor += 1
        names.append(data[cursor:cursor + length].decode("ascii"))
        cursor += length
    return names, cursor


def textures(data):
    labels, cursor = names(data)
    count = len(labels)
    size = struct.unpack_from("<I", data, cursor)[0]
    cursor += 4
    assert size == len(data) - cursor
    frames, flags, layout = struct.unpack_from("<HBB", data, cursor)
    cursor += 4
    assert frames == count and flags == 0 and layout in (0, 1), (frames, flags, layout)
    dimensions = []
    for _ in labels:
        marker, height, width = struct.unpack_from("<BHH", data, cursor)
        cursor += 5
        assert marker == 128 and 0 < width <= 1024 and 0 < height <= 1024
        dimensions.append((width, height))
    result = []
    for name, (width, height) in zip(labels, dimensions):
        encoding = struct.unpack_from("<H", data, cursor)[0]
        cursor += 2
        assert encoding == 1, (name, encoding)
        pixels = np.frombuffer(data, dtype="<u2", count=width * height, offset=cursor).reshape(height, width)
        cursor += width * height * 2
        image = np.empty((height, width, 4), dtype=np.uint8)
        for channel, shift in enumerate((0, 5, 10)):
            image[:, :, channel] = ((pixels >> shift) & 31) * 255 // 31
        image[:, :, 3] = (pixels >> 15) * 255
        result.append((name, Image.fromarray(image)))
    assert cursor == len(data), (cursor, len(data))
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("dump", type=Path)
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--install", action="store_true", help="Save the native photo cutout in the project assets")
    args = parser.parse_args()
    data = args.dump.read_bytes()
    archive = files(data)
    if args.list:
        for name, (_, package) in archive.items():
            if name.startswith("TEXTURE."):
                print(name, names(package)[0])
        return
    output = root / "build/importds"
    output.mkdir(parents=True, exist_ok=True)
    records = []
    splash = None
    for name in ("TEXTURE.Backgrounds.pkg", "TEXTURE.MenuBackgroundPhoto.pkg"):
        offset, package = archive[name]
        for sprite, image in textures(package):
            image.save(output / (sprite + ".png"))
            if sprite == "MenuBackgroundSplash":
                splash = image
            records.append(dict(package=name, offset=offset, sprite=sprite, size=list(image.size),
                                packageSha256=hashlib.sha256(package).hexdigest()))
            print(sprite, image.size)
    (output / "manifest.json").write_text(json.dumps(dict(dumpSha256=hashlib.sha256(data).hexdigest(),
        sprites=records), indent=2))
    if args.install:
        assert splash is not None
        paper = Image.new("L", splash.size)
        ImageDraw.Draw(paper).polygon(((32, 38), (177, 22), (189, 28), (195, 141), (60, 163)), fill=255)
        points = sorted((x, y) for y in range(22, 164) for x in range(30, 197)
                        if paper.getpixel((x, y)) and min(splash.getpixel((x, y))[:3]) >= 230)
        def cross(a, b, c):
            return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
        hull = []
        for sequence in (points, list(reversed(points))):
            side = []
            for point in sequence:
                while len(side) > 1 and cross(side[-2], side[-1], point) <= 0:
                    side.pop()
                side.append(point)
            hull += side[:-1]
        mask = Image.new("L", splash.size)
        ImageDraw.Draw(mask).polygon(hull, fill=255)
        photo = splash.copy()
        photo.putalpha(mask)
        bounds = mask.getbbox()
        photo = photo.crop(bounds).transpose(Image.Transpose.ROTATE_90)
        assert photo.getbbox() == (0, 0, photo.width, photo.height)
        target = root / "assets/feedcandy.png"
        photo.save(target)
        preview = Image.new("RGBA", (photo.width+20, photo.height+20), "#303030")
        preview.alpha_composite(photo, (10, 10))
        preview.save(output / "photo-preview.png")
        (target.with_suffix(".json")).write_text(json.dumps(dict(
            dumpSha256=hashlib.sha256(data).hexdigest(), package="TEXTURE.Backgrounds.pkg",
            sprite="MenuBackgroundSplash", crop=bounds, paperHull=hull, rotation=90,
            note="Native RGB5 pixels from the paper inside the flattened DS splash. No redraw or resampling; exterior tape and background excluded.",
            sha256=hashlib.sha256(target.read_bytes()).hexdigest()), indent=2))
        print("Installed", target, photo.size)


if __name__ == "__main__":
    main()
