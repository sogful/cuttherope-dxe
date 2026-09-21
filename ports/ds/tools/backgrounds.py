import json
from PIL import Image
import colors
from levels import boxes


def build(content, output, sources):
    path = content / "ctroriginal_packs.json"
    sources.add(path)
    configs = json.loads(path.read_text())[:boxes]
    data, offsets, records = bytearray(), [], []
    for box, config in enumerate(configs):
        images = []
        for resource in config["boxBackground"]:
            path = content / "images/backgrounds" / (resource + ".png")
            sources.add(path)
            images.append(Image.open(path).convert("RGBA"))
        first, seam = images[0], images[1] if len(images) > 1 else None
        cover = max(1920 / first.width, 1440 / first.height)
        first = first.resize((round(first.width * cover), round(first.height * cover)), Image.Resampling.LANCZOS)
        if seam:
            seam = seam.resize((round(seam.width * cover), round(seam.height * cover)), Image.Resampling.LANCZOS)
        left = (first.width - 1920) // 2
        first = first.crop((left, 0, left + 1920, 1440)).resize(
            (256, 192), Image.Resampling.LANCZOS
        )
        seam = seam.crop((left, 0, left + 1920, seam.height)).resize(
            (256, round(seam.height * 192 / 1440)), Image.Resampling.LANCZOS
        ) if seam else None
        row = []
        for sections in range(1, 4):
            canvas = Image.new("RGBA", (256, sections * 192 + 64))
            for top in range(0, canvas.height, 192):
                canvas.paste(first, (0, top))
            for index in range(sections - 1 if seam else 0):
                canvas.alpha_composite(
                    seam,
                    (0, round(config.get("boxBackgroundP2Y", 0) * cover * 192 / 1440) + index * 192),
                )
            row.append(len(data))
            data.extend(colors.direct(canvas.convert("RGB")))
            canvas.save(output / f"background{box + 1}x{sections}.png")
            records.append(
                dict(
                    box=box,
                    sections=sections,
                    offset=row[-1],
                    height=canvas.height,
                    seamY=config.get("boxBackgroundP2Y", 0),
                    coverScale=cover,
                    resources=config["boxBackground"],
                )
            )
            if sections == 1:
                canvas.save(
                    output
                    / ("background.png" if box == 0 else f"background{box + 1}.png")
                )
        offsets.append(row)
    (output / "nitro/world.bin").write_bytes(data)
    (output / "backgroundmanifest.json").write_text(json.dumps(records, indent=2))
    return (
        [f"inline constexpr unsigned backgrounds[{boxes}][3] = {{"]
        + ["{" + ",".join(map(str, row)) + "}," for row in offsets]
        + ["};"]
    )


if __name__ == "__main__":
    from assets import content, output
    build(content, output, set())
