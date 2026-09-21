"""Relink baked pages with their palettes in NitroFS, without rerasterizing art."""
import json
from pathlib import Path
import re


def build(output):
    manifestpath = output / "menumanifest.json"
    manifest = json.loads(manifestpath.read_text(encoding="utf-8"))
    blob, rows = bytearray(), []
    saved = 0
    for page in manifest["pages"]:
        page["offset"] = len(blob)
        palette = b"" if page["direct"] else (output/(page["name"]+"palette.bin")).read_bytes()
        assert len(palette) == (0 if page["direct"] else 2 << (8-page["alphabits"]))
        page["palettebytes"] = len(palette)
        data = (output/(page["name"]+".lz")).read_bytes()
        blob.extend(palette); blob.extend(data); saved += len(palette)
        rows.append("{"+",".join(map(str,(page["width"],page["height"],int(page["direct"]),page.get("alphabits",0),page["offset"],len(palette)+len(data))))+"},")
    headerpath = output / "menuassets.hpp"
    header = headerpath.read_text(encoding="utf-8")
    header = re.sub(r"extern const unsigned char menupage\d+palette\[\];\n", "", header)
    header = re.sub(r"struct page \{[^}]*\};", "struct page { std::uint16_t width, height; std::uint8_t direct, alphabits; unsigned offset, packed; };", header)
    header = re.sub(r"inline constexpr page pages\[\] = \{.*?\n\};", "inline constexpr page pages[] = {\n"+"\n".join(rows)+"\n};",header,flags=re.S)
    headerpath.write_text(header,encoding="utf-8")
    (output/"menuassets.s").write_text(".section .rodata\n",encoding="utf-8")
    (output/"nitro/menu.bin").write_bytes(blob)
    manifest["streamedPaletteBytes"] = saved
    manifestpath.write_text(json.dumps(manifest,indent=2,ensure_ascii=False),encoding="utf-8")
    print(f"Streamed {saved:,} palette bytes; page metadata is 16 bytes per page")


if __name__ == "__main__":
    build(Path(__file__).resolve().parents[1]/"generated")
