import argparse
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

root = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--assets", action="store_true", help="Rebuild converted assets")
    parser.add_argument("--reuse-assets", action="store_true", help="Trust a restored generated-asset cache")
    variant = parser.add_mutually_exclusive_group()
    variant.add_argument("--bootcheck", action="store_true", help="Build a separate on-screen/SD-log loader and ROM filesystem probe")
    variant.add_argument("--profile", action="store_true", help="Build separate instrumented ROM without replacing the normal ROM")
    variant.add_argument("--logging", action="store_true", help="Build the full game with persistent hardware diagnostic logs")
    args = parser.parse_args()
    wonderful = root / ".tools/msys64/opt/wonderful"
    sdk = Path(os.environ.get("BLOCKSDS", str(wonderful / "thirdparty/blocksds/core")))
    compiler = wonderful / "toolchain/gcc-arm-none-eabi/bin/arm-none-eabi-g++.exe"
    if not compiler.exists():
        raise SystemExit("Run powershell -File tools/setup.ps1 first.")
    os.chdir(root)
    if args.assets or not (root / "generated/assets.hpp").exists() or not (root / "generated/menuassets.hpp").exists():
        subprocess.run([sys.executable, "tools/assets.py"], check=True)
    import menulayout
    menulayout.update(root/"generated")
    upper = root / "generated/uppermanifest.json"
    upper_stale = not args.reuse_assets and any(path.stat().st_mtime > upper.stat().st_mtime for path in
            (root/"tools/upperart.py",root/"tools/upperhud.py",root/"tools/uppermotion.py",root/"assets/feedcandy.png",root/"generated/menumanifest.json"))
    if args.assets or not upper.exists() or upper_stale:
        subprocess.run([sys.executable, "tools/upperart.py"], check=True)
    build = root / "build" / "logging" if args.logging else root / "build" / "profile" if args.profile else root / "build"
    import backgroundstore
    backgroundstore.update(root/"generated")
    dist = root / "dist"
    build.mkdir(parents=True, exist_ok=True)
    dist.mkdir(exist_ok=True)
    import banner
    icon = banner.update()
    if args.bootcheck:
        import bootassets
        bootassets.build(root/"generated")
    environment = os.environ.copy()
    environment["BLOCKSDS"] = sdk.as_posix()
    environment["PATH"] = str(wonderful / "bin") + os.pathsep + str(wonderful / "runtime/gcc-libs/bin") + os.pathsep + environment["PATH"]
    flags = ["-std=c++17", "-O2", "-g", "-Wall", "-Wextra", "-Werror", "-mthumb", "-mcpu=arm946e-s+nofp",
             "-ffp-contract=off", "-fno-exceptions", "-fno-rtti", "-ffunction-sections", "-fdata-sections",
             "-Iinclude", "-Igenerated", "-I" + str(sdk / "libs/libnds/include"), "-specs=" + str(sdk / "sys/crts/ds_arm9.specs")]
    objects = []
    if args.profile:
        flags.append("-DDS_PROFILE")
    if args.logging:
        flags.extend(("-DDS_LOGGING", "-DDS_PROFILE"))
    sources = [root / "tests/boot.cpp"] if args.bootcheck else sorted((root / "source").glob("*.cpp"))
    def compile_source(source):
        target = build / (source.stem + ".o")
        print("Compile", source.name, flush=True)
        hotflags = ["-marm", "-O3"] if source.stem in ("simulation", "mechanics", "advanced", "frontend", "devices", "upper") else []
        subprocess.run([str(compiler), *flags, *hotflags, "-c", str(source), "-o", str(target)], check=True, env=environment)
        return str(target)
    workers = min(4, os.cpu_count() or 1)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        objects.extend(pool.map(compile_source, sources))
    assets = build / "assets.o"
    subprocess.run([str(compiler), "-mcpu=arm946e-s+nofp", "-c", "generated/assets.s", "-o", str(assets)], check=True, env=environment)
    if not args.bootcheck:
        objects.append(str(assets))
        menus = build / "menuassets.o"
        subprocess.run([str(compiler), "-mcpu=arm946e-s+nofp", "-c", "generated/menuassets.s", "-o", str(menus)], check=True, env=environment)
        objects.append(str(menus))
        library = subprocess.check_output([str(compiler), *flags, "-print-libgcc-file-name"], env=environment, text=True).strip()
        archive = compiler.with_name("arm-none-eabi-ar.exe")
        members = ("_arm_addsubsf3.o", "_arm_muldivsf3.o", "_arm_cmpsf2.o", "_arm_fixsfsi.o", "_arm_fixunssfsi.o")
        subprocess.run([str(archive), "x", library, *members], cwd=build, env=environment, check=True)
        for member in members:
            target = build / (Path(member).stem + ".itcm.o")
            subprocess.run([str(compiler.with_name("arm-none-eabi-objcopy.exe")), str(build / member), str(target)], env=environment, check=True)
            objects.append(str(target))
        # Keep the SDK's exact sqrt and line implementation, relocating only
        # their hot sections. Moving the entire graphics object would waste the
        # small ITCM budget on cold initialization and unrelated drawing code.
        for member, function in (("math.c.o", "hw_sqrtf"), ("gl2d.c.o", "glLine")):
            subprocess.run([str(archive), "x", str(sdk / "libs/libnds/lib/libnds9.a"), member],
                           cwd=build, env=environment, check=True)
            target = build / ("hot-" + member)
            subprocess.run([str(compiler.with_name("arm-none-eabi-objcopy.exe")),
                            "--rename-section", f".text.{function}=.itcm.text.{function}",
                            str(build / member), str(target)], env=environment, check=True)
            objects.append(str(target))
    name = "bootcheck" if args.bootcheck else "cuttherope-logging" if args.logging else "cuttherope-profile" if args.profile else "cuttherope"
    elf = build / (name + ".elf")
    subprocess.run([str(compiler.with_name("arm-none-eabi-gcc.exe")), *flags, *objects, "-L" + str(sdk / "libs/libnds/lib"),
                    "-Wl,-Map=" + str(build / (name + ".map")), "-Wl,--start-group", "-lnds9", "-lstdc++", "-lc", "-lm", "-Wl,--end-group",
                    "-o", str(elf)], check=True, env=environment)
    symbols = subprocess.check_output([str(compiler.with_name("arm-none-eabi-nm.exe")), "-n", str(elf)], env=environment, text=True)
    boundaries = {line.split()[-1]:int(line.split()[0],16) for line in symbols.splitlines()
                  if line.split()[-1] in ("__end__","__eheap_end","__itcm_start","__itcm_end","hw_sqrtf","glLine")}
    if not args.bootcheck:
        free = boundaries["__eheap_end"]-boundaries["__end__"]
        minimum = (120 if args.logging else 128) * 1024
        assert free >= minimum, f"Only {free:,} heap bytes remain in original DS mode"
        print(f"Original DS heap headroom: {free:,} bytes (minimum {minimum:,})",flush=True)
        for function in ("hw_sqrtf", "glLine"):
            assert boundaries["__itcm_start"] <= boundaries[function] < boundaries["__itcm_end"], f"{function} was not placed in ITCM"
        import cachelines
        layout = subprocess.check_output([str(compiler.with_name("arm-none-eabi-nm.exe")), "-S", "-C", "--defined-only", str(elf)], env=environment, text=True)
        cachelines.validate(layout)
        print("SD buffers occupy isolated whole cache lines",flush=True)
    rom = dist / (name + ".nds")
    subprocess.run([str(sdk / "tools/ndstool/ndstool.exe"), "-c", str(rom), "-uc", "2", "-u", "00030000",
                    "-9", str(elf), "-7", str(sdk / "sys/arm7/main_core/arm7_maxmod.elf"),
                    "-d", str(root / "generated/nitro"),
                    "-b", str(icon), banner.title+(";Boot diagnostics" if args.bootcheck else "")], check=True, env=environment)
    import romheader
    romheader.validate(rom.read_bytes())
    size = compiler.with_name("arm-none-eabi-size.exe")
    subprocess.run([str(size), str(elf)], check=True, env=environment)
    (build / ("bootsymbols.txt" if args.bootcheck else "symbols.txt")).write_text(symbols, encoding="utf-8")
    print(f"ROM: {rom} ({rom.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
