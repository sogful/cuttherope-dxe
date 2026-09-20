"""Rank transient frame changes for manual inspection, not a visual pass/fail test."""

import argparse
import json
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageSequence, ImageStat


def distance(a, b):
    return sum(ImageStat.Stat(ImageChops.difference(a, b)).mean) / 3


def inspect(path):
    frames = []
    with Image.open(path) as source:
        for index, item in enumerate(ImageSequence.Iterator(source)):
            image = item.convert("RGB")
            if not frames or distance(frames[-1][1], image) > 0:
                frames.append((index, image))
    candidates = []
    for i in range(1, len(frames) - 1):
        a, b, c = (frames[j][1] for j in (i - 1, i, i + 1))
        score = min(distance(a, b), distance(b, c)) - distance(a, c)
        if score > 0.5:
            candidates.append((score, i))
    candidates.sort(reverse=True)
    selected = candidates[:8]
    if selected:
        width, height = frames[0][1].size
        sheet = Image.new("RGB", (width * 3, (height + 20) * len(selected)), "#222222")
        draw = ImageDraw.Draw(sheet)
        for row, (score, i) in enumerate(selected):
            for col, j in enumerate((i - 1, i, i + 1)):
                sheet.paste(frames[j][1], (col * width, row * (height + 20) + 20))
                draw.text((col * width + 4, row * (height + 20) + 4),
                          f"frame {frames[j][0]} score {score:.2f}", fill="white")
        sheet.save(path.with_name(path.stem + "-transients.png"))
    return {"file": str(path), "frames": len(frames), "candidates": len(candidates),
            "strongest": [{"frame": frames[i][0], "score": score} for score, i in selected]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("files", nargs="+", type=Path)
    args = parser.parse_args()
    print(json.dumps([inspect(path) for path in args.files], indent=2))
