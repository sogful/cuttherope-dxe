import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--assets", action="store_true", help="Rebuild converted assets")
    parser.add_argument("--bootcheck", action="store_true", help="Build a minimal emulator/toolchain compatibility probe")
    args = parser.parse_args()
    wonderful = root / ".tools/msys64/opt/wonderful"
    sdk = Path(os.environ.get("BLOCKSDS", str(wonderful / "thirdparty/blocksds/core")))
    compiler = wonderful / "toolchain/gcc-arm-none-eabi/bin/arm-none-eabi-g++.exe"
    if not compiler.exists():
        raise SystemExit("Run powershell -File tools/setup.ps1 first.")
    os.chdir(root)
    if args.assets or not (root / "generated/assets.hpp").exists() or not (root / "generated/menuassets.hpp").exists():
        subprocess.run([sys.executable, "tools/assets.py"], check=True)
    build = root / "build"
    dist = root / "dist"
    build.mkdir(exist_ok=True)
    dist.mkdir(exist_ok=True)
    environment = os.environ.copy()
    environment["BLOCKSDS"] = sdk.as_posix()
    environment["PATH"] = str(wonderful / "bin") + os.pathsep + str(wonderful / "runtime/gcc-libs/bin") + os.pathsep + environment["PATH"]
    flags = ["-std=c++17", "-O2", "-g", "-Wall", "-Wextra", "-Werror", "-mthumb", "-mcpu=arm946e-s+nofp",
             "-ffp-contract=off", "-fno-exceptions", "-fno-rtti", "-ffunction-sections", "-fdata-sections",
             "-Iinclude", "-Igenerated", "-I" + str(sdk / "libs/libnds/include"), "-specs=" + str(sdk / "sys/crts/ds_arm9.specs")]
    objects = []
    sources = [root / "tests/boot.cpp"] if args.bootcheck else sorted((root / "source").glob("*.cpp"))
    for source in sources:
        target = build / (source.stem + ".o")
        print("Compile", source.name, flush=True)
        hotflags = ["-marm", "-O3"] if source.stem in ("simulation", "mechanics", "advanced") else []
        subprocess.run([str(compiler), *flags, *hotflags, "-c", str(source), "-o", str(target)], check=True, env=environment)
        objects.append(str(target))
    assets = build / "assets.o"
    subprocess.run([str(compiler), "-mcpu=arm946e-s+nofp", "-c", "generated/assets.s", "-o", str(assets)], check=True, env=environment)
    if not args.bootcheck:
        objects.append(str(assets))
        menus = build / "menuassets.o"
        subprocess.run([str(compiler), "-mcpu=arm946e-s+nofp", "-c", "generated/menuassets.s", "-o", str(menus)], check=True, env=environment)
        objects.append(str(menus))
    name = "bootcheck" if args.bootcheck else "cuttherope"
    elf = build / (name + ".elf")
    subprocess.run([str(compiler.with_name("arm-none-eabi-gcc.exe")), *flags, *objects, "-L" + str(sdk / "libs/libnds/lib"),
                    "-Wl,-Map=" + str(build / (name + ".map")), "-Wl,--start-group", "-lnds9", "-lstdc++", "-lc", "-lm", "-Wl,--end-group",
                    "-o", str(elf)], check=True, env=environment)
    rom = dist / (name + ".nds")
    subprocess.run([str(sdk / "tools/ndstool/ndstool.exe"), "-c", str(rom), "-uc", "0",
                    "-9", str(elf), "-7", str(sdk / "sys/arm7/main_core/arm7_maxmod.elf"),
                    "-d", str(root / "generated/nitro"),
                    "-b", str(sdk / "sys/icon.bmp"), "Cut the Rope DX;DS feasibility slice;DX Extended"], check=True, env=environment)
    size = compiler.with_name("arm-none-eabi-size.exe")
    subprocess.run([str(size), str(elf)], check=True, env=environment)
    symbols = subprocess.check_output([str(compiler.with_name("arm-none-eabi-nm.exe")), "-n", str(elf)], env=environment, text=True)
    (build / ("bootsymbols.txt" if args.bootcheck else "symbols.txt")).write_text(symbols, encoding="utf-8")
    print(f"ROM: {rom} ({rom.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
