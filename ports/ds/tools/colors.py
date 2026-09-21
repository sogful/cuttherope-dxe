import struct

from PIL import Image

matrix = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))


def palette(image, count=32, dither=True):
    visible = [pixel[:3] for pixel in image.getdata() if pixel[3] >= 18]
    training = Image.new("RGB", (max(1, len(visible)), 1))
    training.putdata(visible or [(0, 0, 0)])
    rgb = training.quantize(colors=count, method=Image.Quantize.MEDIANCUT).getpalette()[:count * 3]
    rgb += rgb[:3] * ((count * 3 - len(rgb)) // 3)
    packed = [(rgb[i] >> 3) | ((rgb[i + 1] >> 3) << 5) | ((rgb[i + 2] >> 3) << 10) for i in range(0, len(rgb), 3)]
    if dither:
        rgb = [((value >> shift) & 31) * 255 // 31 for value in packed for shift in (0, 5, 10)]
    lookup = Image.new("P", (1, 1))
    lookup.putpalette(rgb * (256 // count))
    return lookup, struct.pack("<" + "H" * count, *packed)


def indexed(image, lookup, dither=True, bits=3, origin=(0, 0)):
    rgb = image.convert("RGB")
    if dither:
        background = tuple(lookup.getpalette()[:3])
        rgb.putdata([pixel[:3] if pixel[3] >= 18 else background for pixel in image.getdata()])
    if dither == "low":
        rgb.putdata([tuple(max(0, min(255, channel + round((matrix[(i // image.width + origin[1]) % 4][(i % image.width + origin[0]) % 4] - 7.5) / 8)))
                           for channel in pixel) for i, pixel in enumerate(rgb.getdata())])
    # Small repeated textures need stable pixel clusters. Error diffusion plus
    # alpha dithering makes single-pixel holes flicker as a conveyor scrolls.
    if dither == "pixel":
        rgb.putdata([tuple(max(0,min(255,channel + round((matrix[(i//image.width+origin[1])%4][(i%image.width+origin[0])%4]-7.5)/2)))
                          for channel in pixel) for i,pixel in enumerate(rgb.getdata())])
    indices = rgb.quantize(palette=lookup, dither=Image.Dither.FLOYDSTEINBERG if dither is True else Image.Dither.NONE)
    maximum, shift = (1 << bits) - 1, 8 - bits
    result = bytearray()
    for index, (alpha, color) in enumerate(zip(image.getchannel("A").getdata(), indices.getdata())):
        if dither is True:
            threshold = (matrix[(index // image.width + origin[1]) % 4][(index % image.width + origin[0]) % 4] + .5) / 16
            opacity = min(maximum, int(alpha * maximum / 255 + threshold))
        else:
            opacity = round(alpha * maximum / 255)
        result.append((opacity << shift) | (color & ((1 << shift) - 1)))
    return bytes(result)


def direct(image):
    result = bytearray()
    for index, pixel in enumerate(image.convert("RGB").getdata()):
        threshold = (matrix[index // image.width % 4][index % image.width % 4] + .5) / 16
        values = [min(31, int(value * 31 / 255 + threshold)) for value in pixel]
        result.extend(struct.pack("<H", 0x8000 | values[0] | (values[1] << 5) | (values[2] << 10)))
    return bytes(result)
