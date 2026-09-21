"""Upper-only, final-resolution HUD art; never upscale lower-screen textures."""
import math
import numpy as np
from PIL import Image, ImageDraw
import assets
import menus
import uiscale


def build():
    images, records = [], []
    def add(image, origin, advance=0):
        bounds=image.getbbox()
        crop=image.crop(bounds)
        records.append((sum(item.width*item.height for item in images),crop.width,crop.height,
                        round(bounds[0]-origin[0]),round(bounds[1]-origin[1]),round(advance)))
        images.append(crop)
    ratio=menus.fit*uiscale.hud*menus.scale*2.5
    for frame in range(1,12):
        source,_=assets.readframe("hud_ui",frame)
        size=tuple(round(value*ratio) for value in source.size)
        image=source.resize(size,Image.Resampling.LANCZOS)
        add(image,(image.width/2,image.height/2))
    face,_=menus.font("en")
    ratio=menus.fit*uiscale.results*menus.scale*1.65
    for digit in range(10):
        width=face.getlength(str(digit))
        canvas=Image.new("RGBA",(math.ceil(width)+20,125))
        ImageDraw.Draw(canvas).text((10,15+face.getmetrics()[0]),str(digit),font=face,anchor="ls",
                                   fill="white",stroke_width=round(1/ratio),stroke_fill="black")
        image=canvas.resize(tuple(round(value*ratio) for value in canvas.size),Image.Resampling.LANCZOS)
        add(image,((10+width/2)*ratio,62.5*ratio),width*ratio)
    return images,records


def encode(images,lookup):
    result=bytearray()
    for image in images:
        source=np.asarray(image,dtype=np.uint16)
        rgb=(source[:,:,:3]*31+127)//255
        color=lookup[rgb[:,:,0]|(rgb[:,:,1]<<5)|(rgb[:,:,2]<<10)].astype(np.uint16)
        alpha=(source[:,:,3]*31+127)//255
        result.extend((color|(alpha<<8)).astype("<u2").tobytes())
    return result
