"""Silent, windowless DS ROM integration test using the melonDS DS libretro core."""
import argparse
import ctypes as c
import hashlib
import json
import math
from pathlib import Path
import struct
import time

from PIL import Image, ImageChops

root = Path(__file__).resolve().parents[1]


class variable(c.Structure):
    _fields_ = [("key", c.c_char_p), ("value", c.c_char_p)]


class option(c.Structure):
    _fields_ = [("key", c.c_char_p), ("desc", c.c_char_p), ("categorydesc", c.c_char_p),
                ("info", c.c_char_p), ("categoryinfo", c.c_char_p), ("category", c.c_char_p),
                ("values", variable * 128), ("default", c.c_char_p)]


class options(c.Structure):
    _fields_ = [("categories", c.c_void_p), ("definitions", c.POINTER(option))]


class gameinfo(c.Structure):
    _fields_ = [("path", c.c_char_p), ("data", c.c_void_p), ("size", c.c_size_t), ("meta", c.c_char_p)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--core", default=str(root / ".tools/libretro/melondsds_libretro.dll"))
    parser.add_argument("--rom", default=str(root / "dist/cuttherope.nds"))
    parser.add_argument("--inspect", action="store_true")
    parser.add_argument("--menus", action="store_true", help="Check source-shaped title, packs, settings, languages and credits")
    parser.add_argument("--skins", action="store_true", help="Check fades, isolated unlock mode, picker scrolling, all cosmetic tabs and equipped gameplay")
    parser.add_argument("--flow", action="store_true", help="Capture box transitions and the complete animated result sequence")
    parser.add_argument("--boxes", action="store_true", help="Launch all 400 maps across the first sixteen boxes")
    parser.add_argument("--startup", action="store_true", help="Capture consecutive frames through early level texture paging")
    parser.add_argument("--regressions", action="store_true", help="Exercise outcome input races, flashes, costume voices, carousel and tall backgrounds")
    parser.add_argument("--profile", action="store_true", help="Read optional profiling build and capture framebuffer changes during stalled main updates")
    parser.add_argument("--pagingstress", action="store_true", help="Profile-only synthetic heavy completion and captured-frame recovery test")
    parser.add_argument("--first-box", type=int, default=1, choices=range(1,17))
    parser.add_argument("--last-box", type=int, default=16, choices=range(1,17))
    parser.add_argument("--level-only", type=int, choices=range(1,26), help="Limit box checks to one level number")
    parser.add_argument("--costume", type=int, default=0, choices=range(16), help="Equip a costume through the real picker before a test")
    parser.add_argument("--soak", type=int, default=3600, help="Additional idle frames before interaction tests")
    args = parser.parse_args()
    if args.pagingstress and not args.profile:
        parser.error("--pagingstress requires --profile; normal ROMs have no diagnostic controls")
    if args.profile and args.rom == str(root / "dist/cuttherope.nds"):
        args.rom = str(root / "dist/cuttherope-profile.nds")
    core = c.CDLL(args.core)
    directory = root / "build/headless" / "profile" if args.profile else root / "build/headless"
    if args.profile:
        label = f"pagingstress-{args.first_box}-{args.level_only or 23}" if args.pagingstress else f"boxes-{args.first_box}-{args.last_box}-{args.level_only or 'all'}" if args.boxes else "regressions" if args.regressions else "flow" if args.flow else "inspect"
        directory /= label + f"-costume-{args.costume}"
    directory.mkdir(parents=True, exist_ok=True)
    folder = str(directory).encode()
    system = directory / "system"
    system.mkdir(exist_ok=True)
    systemfolder = str(system).encode()
    values = {}
    frame = None
    pixel = 1
    pointer = [0, 0, 0]
    buttons = set()
    audioframes = 0
    audiononzero = 0
    messages = []
    callbacks = []
    animation = []
    logo = Image.open(root / "generated/logo.png").convert("RGB")

    def callback(name, restype, types, function):
        instance = c.CFUNCTYPE(restype, *types)(function)
        callbacks.append(instance)
        getattr(core, name).argtypes = [type(instance)]
        getattr(core, name)(instance)

    def write(data, kind, value):
        c.cast(data, c.POINTER(kind))[0] = value
        return True

    def environment(command, data):
        nonlocal pixel
        cmd = command & 0xffff
        if cmd in (9, 30, 31):
            return write(data, c.c_char_p, systemfolder if cmd == 9 else folder)
        if cmd in (3, 74):
            return write(data, c.c_bool, True)
        if cmd in (2, 17, 49):
            return write(data, c.c_bool, False)
        if cmd == 52:
            return write(data, c.c_uint, 2)
        if cmd in (39, 56, 59):
            return write(data, c.c_uint, 0)
        if cmd == 61:
            return write(data, c.c_uint, 1)
        if cmd == 47:
            return write(data, c.c_int, 3)
        if cmd == 10:
            pixel = c.cast(data, c.POINTER(c.c_int))[0]
            return pixel == 1
        if cmd == 67:
            definitions = c.cast(data, c.POINTER(options)).contents.definitions
            index = 0
            while definitions[index].key:
                item = definitions[index]
                value = item.default or item.values[0].key
                choices = [pair.key for pair in item.values if pair.key]
                key = item.key.decode()
                if key in ("melonds_homebrew_sdcard", "melonds_dsi_sdcard", "melonds_show_cursor") and b"disabled" in choices:
                    value = b"disabled"
                if "sysfile" in key:
                    value = next((choice for choice in choices if choice != b"native"), value)
                if "render" in key and b"software" in choices:
                    value = b"software"
                if "cursor" in key and "mode" in key and b"disabled" in choices:
                    value = b"disabled"
                if key == "melonds_network_mode" and b"disabled" in choices:
                    value = b"disabled"
                values[item.key] = value
                index += 1
            print("Core configured: DS, software rendering, silent output", flush=True)
            return True
        if cmd == 15:
            item = c.cast(data, c.POINTER(variable)).contents
            item.value = values.get(item.key)
            return item.value is not None
        if cmd in (6, 60):
            message = c.cast(data, c.POINTER(c.c_char_p))[0]
            messages.append(message.decode(errors="replace"))
            print("Core:", messages[-1], flush=True)
            return True
        if cmd in (1, 8, 11, 18, 21, 32, 34, 35, 36, 37, 42, 55, 58, 63, 65, 69):
            return True
        return False

    def video(data, width, height, pitch):
        nonlocal frame
        if data:
            frame = (c.string_at(data, height * pitch), width, height, pitch)

    def audio(data, count):
        nonlocal audioframes, audiononzero
        audioframes += count
        if any(c.string_at(data, count * 4)):
            audiononzero += count
        return count

    def inputstate(port, device, index, ident):
        if port != 0:
            return 0
        if device == 1:
            return int(ident in buttons)
        if device == 6 and index == 0:
            return pointer[ident] if ident < 3 else int(bool(pointer[2])) if ident == 3 else 0
        return 0

    callback("retro_set_environment", c.c_bool, [c.c_uint, c.c_void_p], environment)
    callback("retro_set_video_refresh", None, [c.c_void_p, c.c_uint, c.c_uint, c.c_size_t], video)
    callback("retro_set_audio_sample", None, [c.c_int16, c.c_int16], lambda left, right: None)
    callback("retro_set_audio_sample_batch", c.c_size_t, [c.c_void_p, c.c_size_t], audio)
    callback("retro_set_input_poll", None, [], lambda: None)
    callback("retro_set_input_state", c.c_int16, [c.c_uint] * 4, inputstate)
    core.retro_load_game.argtypes = [c.POINTER(gameinfo)]
    core.retro_load_game.restype = c.c_bool
    core.retro_get_memory_data.argtypes = [c.c_uint]
    core.retro_get_memory_data.restype = c.c_void_p
    core.retro_get_memory_size.argtypes = [c.c_uint]
    core.retro_get_memory_size.restype = c.c_size_t
    core.retro_init()
    loaded = False
    profiler = None
    try:
        path = Path(args.rom)
        rom = c.create_string_buffer(path.read_bytes())
        assert rom.raw[0x12] == 0, "The feasibility build must have a DS-only ROM header"
        info = gameinfo(str(path).encode(), c.cast(rom, c.c_void_p), len(rom) - 1, None)
        loaded = core.retro_load_game(c.byref(info))
        if not loaded:
            raise RuntimeError("melonDS rejected the ROM: " + repr(messages))
        def framebuffer():
            if not frame:
                raise RuntimeError("No video frames")
            data, width, height, pitch = frame
            return Image.frombytes("RGB", (width, height), data, "raw", "BGRX", pitch)
        def capture(label):
            image = framebuffer()
            assert image.size == (256, 384), image.size
            difference = ImageChops.difference(image.crop((0, 0, 256, 192)), logo)
            assert max(high for low, high in difference.getextrema()) <= 8, "Upper display does not match the logo within RGB15 precision"
            image.save(directory / (label + ".png"))
            image.crop((0, 192, 256, 384)).save(directory / (label + "-game.png"))
        symbols = (root / ("build/profile/symbols.txt" if args.profile else "build/symbols.txt")).read_text().splitlines()
        address = int(next(line.split()[0] for line in symbols if line.endswith(" telemetry")), 16)
        report = {"core": str(Path(args.core).resolve()), "coreSha256": hashlib.sha256(Path(args.core).read_bytes()).hexdigest(),
                  "romSha256": hashlib.sha256(path.read_bytes()).hexdigest(), "console": "DS", "muted": True, "headless": True, "stages": {}}
        keys = ["magic", "version", "frames", "ticks", "state", "stars", "micros", "peak", "late", "vblanks", "x", "y", "cuts", "touches", "resets", "paused",
                "view", "effects", "music", "score", "bestscore", "beststars", "locale", "pack", "clickcut", "scroll", "texturebytes",
                "unlocked", "skintab", "candy", "rope", "costume", "trace", "skinoffset", "transition", "storage", "door", "doorframe", "menuage", "improved",
                "level", "visuals", "bubble", "pumps", "ropes", "failure", "intro", "cameray", "hooks", "split", "merges", "teleports", "bounces", "rail", "flash", "flashframe", "voices", "voice", "repacks", "renderfault"]
        memory = core.retro_get_memory_data(2)
        size = core.retro_get_memory_size(2)
        offset = address - 0x02000000
        if not memory or offset + 264 > size:
            raise RuntimeError(f"Cannot read telemetry: RAM={size} address={address:x}")
        assert size == 4 * 1024 * 1024, f"Expected original DS main RAM, received {size} bytes"
        if args.profile:
            import profilecapture
            def readprofile(name):
                location = int(next(line.split()[0] for line in symbols if line.endswith(" " + name)), 16)
                return struct.unpack("<32I", c.string_at(memory + location - 0x02000000, 128))
            profiler = profilecapture.recorder(directory, report, readprofile, framebuffer)
        report["mainRamBytes"] = size
        references = json.loads((root.parent / "roblox/tests/desktop-trajectories.json").read_text())
        reference = {sample["tick"]: sample for trace in references if trace["level"] == 1 for sample in trace["samples"]}
        samples = {}
        mapreferences = {trace["level"] - 1: {sample["tick"]: sample for sample in trace["samples"]} for trace in references}
        maperrors = {}
        referenceattempt = 1
        lastframe, stalled = -1, 0
        keys += ["gravity", "gravityevents", "wheel", "wheelevents", "wheelparts", "wheellength"]
        keys += ["spikeevents", "spikebutton", "beex", "beey", "spiderfalls", "spiderclimbers", "fadephase"]
        keys += ["disc", "discangle", "discevents", "ghostforms", "ghostevents", "ghostapps", "bodypool"]
        keys += ["steamevents", "steamstates", "captures", "releases", "occupied", "shared", "lanternx", "lanterny"]
        keys += ["mouse", "mousecaptures", "mousereleases", "mousehandoffs", "mousecarry", "bulb", "bulbx", "bulby", "awake", "lit"]
        faultsymbol = next((line for line in symbols if line.endswith(" renderfault")), None)
        faultaddress = memory + int(faultsymbol.split()[0], 16) - 0x02000000 if faultsymbol else None
        def telemetry():
            version = struct.unpack("<I", c.string_at(memory + offset + 4, 4))[0]
            fields = 86 if version >= 14 else 76 if version >= 13 else 68 if version >= 12 else 61 if version >= 11 else 54 if version >= 10 else 48 if version >= 9 else 46 if version >= 8 else 42
            result = dict(zip(keys, struct.unpack(f"<10I2f{fields}I", c.string_at(memory + offset, 48 + fields * 4))))
            for key in keys: result.setdefault(key, 0)
            return result
        def run(count):
            nonlocal lastframe, stalled
            for _ in range(count):
                core.retro_run()
                current = telemetry()
                stalled = stalled + 1 if current["frames"] == lastframe else 0
                lastframe = current["frames"]
                fault = struct.unpack("<I", c.string_at(faultaddress, 4))[0] if faultaddress else 0
                if fault:
                    values = {}
                    for symbol in symbols:
                        name = symbol.split()[-1]
                        if not any(part in name for part in ("frontendL", "displayL")): continue
                        if any(part in name for part in ("stagedbytes", "transfercount", "reserved", "occupied", "backgroundtop", "backgroundsections")):
                            location = memory + int(symbol.split()[0], 16) - 0x02000000
                            values[name] = struct.unpack("<I", c.string_at(location, 4))[0]
                    (directory / "renderfault.json").write_text(json.dumps(dict(fault=fault, state=current, values=values), indent=2))
                assert not fault and stalled < 120, f"ROM main loop stalled/cache fault={fault:#x}: {current}"
                if profiler:
                    profiler.observe(current)
                tick = current["ticks"]
                if args.boxes and current["view"] == 0 and current["level"] in mapreferences:
                    expected = mapreferences[current["level"]].get(tick)
                    if expected and (current["level"] != 5 or tick <= 60):
                        error = math.hypot(current["x"] - expected["x"], current["y"] - expected["y"])
                        assert error < .05, (current["level"], tick, error)
                        maperrors[(current["level"], tick)] = error
                if tick in reference and tick not in samples and current["resets"] == referenceattempt:
                    samples[tick] = current
                if current["resets"] == referenceattempt and current["view"] == 0 and 10 <= tick < 124 and tick % 3 == 1:
                    animation.append(framebuffer().crop((0, 192, 256, 384)))
        def snapshot(label):
            run(3)  # Allow submitted 3D frames to reach the display after a UI transition.
            result = telemetry()
            report["stages"][label] = result
            print(label, result, flush=True)
            capture(label)
            return result
        start = time.monotonic()
        def touch(x, y, held=True):
            pointer[:] = [round(x / 255 * 65534 - 32767), round((192 + y) / 383 * 65534 - 32767), int(held)]
            run(3)
        def tap(x, y):
            settle()
            touch(x, y)
            touch(x, y, False)
            run(36)
        def key(ident):
            settle()
            buttons.add(ident)
            before = telemetry()["frames"]
            while telemetry()["frames"] < before + 2: run(1)
            buttons.clear()
            run(36)
        def settle():
            for _ in range(360):
                current = telemetry()
                if not current["door"] and not current["transition"] and not current["flash"] and not (current["view"] == 2 and current["menuage"] < 32):
                    return
                run(1)
            raise AssertionError("Transition failed to finish: " + repr(telemetry()))
        if args.regressions or args.startup:
            from PIL import ImageStat
            boot = []
            for _ in range(60):
                run(1)
                boot.append(framebuffer().crop((0,192,256,384)))
            boot[0].save(directory / 'boot-reveal.gif', save_all=True, append_images=boot[1:], duration=17, loop=0)
            brightness = [sum(ImageStat.Stat(item).mean)/3 for item in boot]
            report['bootBrightness'] = brightness
            # The emulator powers on with a white framebuffer before ARM9 has
            # entered main. Inspect our black-loading -> title handoff only.
            firstblack = next(i for i,value in enumerate(brightness) if value < 1)
            assert all(value < 1 or value > 80 for value in brightness[firstblack:]), ('Unexpected boot fade', brightness)
        else:
            run(60)
        for _ in range(120):
            if telemetry()["frames"] > 40: break
            run(1)
        title = snapshot("title")
        if args.costume:
            tap(147,91); tap(153,16)
            for _ in range(args.costume): key(7)
            assert telemetry()["costume"] == args.costume
            key(0)
        assert title["view"] == 5 and title["ticks"] == 0 and title["frames"] > 40, title
        if args.pagingstress:
            import pagingstress
            control = memory + int(next(line.split()[0] for line in symbols if line.endswith(" profilestress")), 16) - 0x02000000
            def stress(value):
                c.cast(control, c.POINTER(c.c_uint))[0] = value
            pagingstress.check(run, tap, key, telemetry, framebuffer, settle, stress, profiler, report, directory,
                               args.first_box, args.level_only or 23)
            return
        if args.regressions:
            import regressions
            regressions.check(run, tap, key, touch, telemetry, framebuffer, snapshot, settle, report, directory)
            return
        if args.boxes:
            import xml.etree.ElementTree as xml
            tap(128,170)
            tap(131,185)
            assert telemetry()["unlocked"]
            key(0); key(8); key(8)
            assert args.first_box <= args.last_box
            if args.first_box > 1:
                key(0)
                for _ in range(args.first_box - 1): key(7)
                run(180); key(8)
            for box in range(args.first_box - 1,args.last_box):
                for level in ([args.level_only - 1] if args.level_only else range(25)):
                    assert telemetry()["view"] == 4 and telemetry()["pack"] == box
                    tap(round(128 + (824 + (level % 5) * 228 - 1280) * 1.01846195 * 192 / 1440),
                        round(96 + (203.5 + (level // 5) * 258 - 720) * 1.01846195 * 192 / 1440))
                    settle()
                    for _ in range(1200):
                        if not telemetry()["intro"]: break
                        run(1)
                    run(70)
                    if box == 0 and level in (0,5,6,9):
                        for _ in range(600):
                            if telemetry()["ticks"] >= 120: break
                            run(1)
                    stage = snapshot(f"map-{box+1}-{level+1}")
                    assert stage["level"] == box * 25 + level and stage["visuals"] > 0
                    assert math.isfinite(stage["x"]) and math.isfinite(stage["y"])
                    assert not stage["intro"], "Tall level introduction never handed control back"
                    if box == 12 and level == 0:
                        before = telemetry()
                        for state in (1,2,0):
                            tap(126,177)
                            result = snapshot("steam-valve-"+str(state))
                            assert result["steamevents"] == before["steamevents"]+1 and result["steamstates"] & 3 == state and result["cuts"] == before["cuts"], result
                            before = result
                    if box == 13 and level == 0:
                        touch(162,80); touch(180,80); touch(180,80,False)
                        for _ in range(300):
                            if telemetry()["shared"]: break
                            run(1)
                        captured = snapshot("lantern-captured")
                        assert captured["occupied"] and captured["shared"] and captured["captures"], captured
                        tap(85,68)
                        released = snapshot("lantern-released")
                        assert released["releases"] and not released["occupied"] and not released["shared"], released
                    if box == 10 and level == 0:
                        initial = telemetry()
                        center = (128.4,92)
                        radius = 48
                        touch(center[0]+radius*math.cos(-math.pi/12),center[1]+radius*math.sin(-math.pi/12))
                        pressed = snapshot("dj-handle-pressed")
                        assert pressed["disc"] == 1, pressed
                        for step in range(1,15):
                            angle = -math.pi/12+step*.08
                            touch(center[0]+radius*math.cos(angle),center[1]+radius*math.sin(angle))
                        moved = snapshot("dj-disc-rotated")
                        assert moved["discangle"] != initial["discangle"] and moved["discevents"] > 0 and moved["cuts"] == initial["cuts"], moved
                        touch(center[0],center[1],False)
                        run(5)
                        assert not telemetry()["disc"]
                    if box == 11 and level == 0:
                        document = xml.parse(root.parents[1] / "content/maps/12_1.xml")
                        ghost = document.find("./layer[@name='Objects']/ghost")
                        width = float(document.find("./layer[@name='settings']/map").get("width"))
                        point = (128+(float(ghost.get("x"))-width/2)*.4,float(ghost.get("y"))*.4-telemetry()["cameray"]*192/1440)
                        before = telemetry()
                        tap(*point); run(20)
                        appeared = snapshot("spooky-bubble-form")
                        assert appeared["ghostevents"] > before["ghostevents"] and appeared["ghostforms"] & 15 == 2 and appeared["ghostapps"], appeared
                        tap(*point); run(20)
                        changed = snapshot("spooky-bouncer-form")
                        assert changed["ghostforms"] & 15 == 8 and changed["ghostevents"] > appeared["ghostevents"], changed
                        tap(*point); run(20)
                        snapshot("spooky-bubble-returned")
                    if box == 8 and level == 0:
                        before = telemetry()["cuts"]
                        touch(104,146)
                        pressed = snapshot("tool-button-pressed")
                        assert pressed["spikebutton"] == 1, pressed
                        touch(170,146); touch(104,146,False)
                        assert telemetry()["spikeevents"] == 0
                        tap(104,146); run(20)
                        assert telemetry()["spikeevents"] == 1 and telemetry()["cuts"] == before
                        snapshot("tool-rotated")
                        tap(104,146); run(20)
                        assert telemetry()["spikeevents"] == 2
                    if box == 9 and level == 0:
                        initial = telemetry(); frames = []
                        for _ in range(90):
                            run(1); frames.append(framebuffer().crop((0,192,256,384)))
                        moved = snapshot("buzz-moving")
                        assert (moved["beex"],moved["beey"]) != (initial["beex"],initial["beey"])
                        frames[0].save(directory / "buzz-path.gif",save_all=True,append_images=frames[1:],duration=17,loop=0)
                    if box == 6 and level == 11:
                        rotations = []
                        for _ in range(120):
                            run(1)
                            rotations.append(framebuffer().crop((0,192,256,384)))
                        rotations[0].save(directory / "gift-rotating-spikes.gif", save_all=True,
                                          append_images=rotations[1:], duration=17, loop=0)
                        strip = Image.new("RGB", (256 * 6, 192))
                        for column, index in enumerate(range(0,120,20)): strip.paste(rotations[index], (column * 256,0))
                        strip.save(directory / "gift-rotating-spikes.png")
                    if box == 6 and level == 0:
                        before = telemetry()["cuts"]
                        center = (131,164)
                        touch(center[0]+10,center[1])
                        assert telemetry()["wheel"] == 1
                        original = telemetry()["wheelparts"]
                        for step in range(180):
                            angle = -step * math.pi / 8
                            touch(center[0]+10*math.cos(angle),center[1]+10*math.sin(angle))
                        touch(center[0]+10,center[1],False)
                        result = snapshot("gift-wheel-retracted")
                        assert result["wheelevents"] > 100 and result["wheelparts"] < original and result["cuts"] == before and not result["wheel"], result
                    if box == 7 and level == 0:
                        before = telemetry()["cuts"]
                        tap(60,157)
                        result = snapshot("cosmic-gravity-inverted")
                        assert result["gravity"] and result["gravityevents"] == 1 and result["cuts"] == before, result
                        run(30)
                        tap(60,157)
                        assert not telemetry()["gravity"] and telemetry()["gravityevents"] == 2
                    if box == 1 and level == 0:
                        before = telemetry()["pumps"]
                        pump = xml.parse(root.parents[1] / "content/maps/2_1.xml").find("./layer[@name='Objects']/pump")
                        tap(64 + float(pump.get("x")) * .4, float(pump.get("y")) * .4)
                        assert telemetry()["pumps"] > before, "Pump touch did not reach gameplay"
                    if box == 2 and level == 0:
                        touch(90,96)
                        assert telemetry()["rail"] == 1, "Rail handle did not capture the stylus"
                        for px in range(90,155,4): touch(px,96)
                        snapshot("foil-dragged-rail")
                        touch(154,96,False)
                        assert telemetry()["rail"] == 0, "Rail did not release the stylus"
                    if box == 3 and level == 0:
                        while telemetry()["ticks"] < 120: run(1)
                        touch(77,44); touch(96,44); touch(96,44,False)
                        for _ in range(800):
                            if telemetry()["view"] == 2: break
                            run(1)
                        result = snapshot("magic-hat-win")
                        assert result["teleports"] == 1 and result["state"] == 1 and result["stars"] == 3, result
                        run(420)
                        snapshot("magic-result-finished")
                    if box == 4 and level == 0:
                        while telemetry()["ticks"] < 120: run(1)
                        touch(97,35); touch(164,35); touch(164,35,False)
                        for _ in range(1200):
                            if telemetry()["merges"]: break
                            run(1)
                        result = snapshot("valentine-merged")
                        assert result["merges"] == 1 and not result["split"], result
                        touch(114,73); touch(146,73); touch(146,73,False)
                        for _ in range(800):
                            if telemetry()["view"] == 2: break
                            run(1)
                        result = snapshot("valentine-win")
                        assert result["state"] == 1 and result["stars"] == 3, result
                        run(420)
                        snapshot("valentine-result-finished")
                    if box >= 12 and level == 24 and telemetry()["view"] == 0:
                        key(3); tap(128,72); settle()
                        skipped = snapshot(f"skip-last-{box+1}")
                        assert skipped["view"] == 4 and skipped["level"] == box*25+24, skipped
                    if telemetry()["view"] == 0: key(3)
                    current = telemetry()["view"]
                    if current == 1: tap(128,96)
                    elif current in (2,3):
                        # Results block input while the first 32 flap frames play.
                        while telemetry()["view"] == 2 and telemetry()["menuage"] < 32: run(1)
                        key(0)
                    settle()
                    run(10)
                    assert telemetry()["view"] == 4, telemetry()
                if box < args.last_box - 1:
                    key(0); key(7); run(180); key(8)
            if args.first_box == 1 and not args.level_only:
                assert len(maperrors) >= 31, "Missing emulated multi-rope reference samples"
            if args.last_box == 6 and not args.level_only:
                assert any(item["bounces"] for item in report["stages"].values()), "No bouncer contact observed"
            maps = (args.last_box - args.first_box + 1) * (1 if args.level_only else 25)
            report.update(passed=True, maps=maps, referenceSamples=len(maperrors), maximumDesktopError=max(maperrors.values(),default=0), seconds=time.monotonic()-start)
            filename = "boxreport" + ("" if maps == 400 else f"-{args.first_box}-{args.last_box}-{args.level_only or 'all'}") + ".json"
            (directory / filename).write_text(json.dumps(report, indent=2), encoding="utf-8")
            print(f"PASS: {maps} maps launched through real UI, boxes {args.first_box}-{args.last_box}")
            return
        if args.skins:
            fades = []
            touch(128, 170)
            touch(128, 170, False)
            for _ in range(40):
                run(1)
                fades.append(framebuffer().crop((0, 192, 256, 384)))
            means = [sum(sum(pixel) for pixel in item.getdata()) / (256 * 192 * 3) for item in fades]
            assert min(means) < 1 and max(means) < 190 and len({round(value) for value in means}) > 8, means
            fades[0].save(directory / "black-fade.gif", save_all=True, append_images=fades[1:], duration=17, loop=0)
            assert telemetry()["view"] == 7 and not telemetry()["transition"]
            tap(131, 185)
            assert snapshot("unlock-enabled")["unlocked"] == 1
            key(0)
            key(8)
            key(7)
            run(180)
            key(8)
            assert snapshot("unlocked-fabric-levels")["pack"] == 1 and telemetry()["view"] == 4
            key(0)
            for _ in range(15): key(7)
            run(180)
            key(8)
            tap(66, 26)
            assert telemetry()["view"] == 4 and telemetry()["resets"] == 0, "An unavailable map silently launched 1-1"
            key(0)
            for _ in range(16): key(6)
            run(180)
            key(0)
            tap(128, 170)
            tap(131, 185)
            assert telemetry()["unlocked"] == 0
            key(0)
            tap(147, 91)
            assert snapshot("picker-candies")["view"] == 11
            def scrollbottom():
                for _ in range(8):
                    touch(128, 150)
                    touch(128, 90)
                    touch(128, 40)
                    touch(128, 40, False)
                run(45)
            scrollbottom()
            tap(187, 149)
            assert snapshot("picker-candy-last")["candy"] == 51
            tap(103, 16)
            scrollbottom()
            tap(69, 149)
            assert snapshot("picker-rope-last")["rope"] == 8
            tap(153, 16)
            assert snapshot("picker-costumes")["skintab"] == 2
            classic = []
            for _ in range(60):
                run(1)
                classic.append(framebuffer().crop((48, 226, 90, 277)))
            classic[0].save(directory / "classic-preview.gif", save_all=True, append_images=classic[1:], duration=16, loop=0)
            strip = Image.new("RGB", (42 * 20, 51))
            for i, item in enumerate(classic[::3]): strip.paste(item, (42 * i, 0))
            strip.save(directory / "classic-preview-strip.png")
            scrollbottom()
            tap(187, 149)
            assert snapshot("picker-costume-last")["costume"] == 15
            run(120)
            snapshot("picker-costume-animated")
            tap(202, 16)
            scrollbottom()
            tap(148, 149)
            assert snapshot("picker-trace-last")["trace"] == 10
            key(0)
            assert snapshot("equipped-title")["view"] == 5
            key(8)
            key(8)
            key(8)
            run(90)
            assert snapshot("equipped-game")["view"] == 0
            touch(100, 40)
            for x in range(105, 156, 5):
                touch(x, 40)
            touch(155, 40, False)
            run(200)
            assert snapshot("equipped-win")["state"] == 1
            report.update(passed=True, skinChecks=True, fadeMeans=means, seconds=time.monotonic() - start)
            (directory / "skinreport.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
            print("PASS: gradual black fade, unlock mode, original box covers, four picker tabs, scrolling, equipment, animated costume, equipped gameplay/win")
            return
        if args.menus:
            tap(128, 170)
            settings = snapshot("options")
            assert settings["view"] == 7
            tap(104, 28)
            tap(152, 28)
            run(60)
            silence = audiononzero
            run(60)
            assert telemetry()["effects"] == telemetry()["music"] == 0 and audiononzero == silence
            tap(148, 150)
            assert telemetry()["clickcut"] == 1
            snapshot("options-muted")
            tap(128, 53)
            assert snapshot("languages")["view"] == 8
            for locale in range(12):
                tap((72, 128, 184)[locale % 3], (59, 84, 108, 133)[locale // 3])
                assert telemetry()["locale"] == locale
                key(0)
                localized = snapshot("options-locale-" + str(locale))
                assert localized["view"] == 7 and localized["locale"] == locale
                assert localized["texturebytes"] <= 384 * 1024
                tap(128, 53)
            tap(128, 59)
            assert snapshot("languages-russian")["locale"] == 1
            tap(72, 133)
            assert snapshot("languages-japanese")["locale"] == 9
            key(0)
            assert snapshot("options-japanese")["view"] == 7
            tap(128, 102)
            assert snapshot("credits-japanese")["view"] == 9
            key(0)
            tap(128, 53)
            tap(72, 59)
            key(0)
            tap(128, 102)
            credits = snapshot("credits")
            assert credits["view"] == 9 and credits["locale"] == 0
            touch(128, 145)
            touch(128, 40)
            touch(128, 40, False)
            scrolled = snapshot("credits-scrolled")
            assert scrolled["scroll"] > credits["scroll"] + 50
            run(30)
            assert telemetry()["scroll"] == scrolled["scroll"], "Touch did not stop credits auto-scroll"
            for _ in range(8):
                touch(128, 145)
                touch(128, 40)
                touch(128, 40, False)
            assert snapshot("credits-end")["scroll"] == 704 - 146
            key(0)
            tap(128, 77)
            assert snapshot("reset-confirmation")["view"] == 10
            tap(128, 138)
            assert telemetry()["view"] == 7
            tap(104, 28)
            tap(152, 28)
            tap(148, 150)
            key(0)
            tap(128, 145)
            assert snapshot("boxes")["view"] == 6
            tap(231, 96)
            run(180)
            assert snapshot("boxes-fabric")["pack"] == 1
            tap(128, 96)
            assert telemetry()["view"] == 6, "Locked pack opened"
            touch(170, 96)
            touch(150, 96)
            touch(120, 96)
            touch(120, 96, False)
            run(180)
            assert snapshot("boxes-swiped")["pack"] == 2
            for _ in range(14):
                key(7)
                run(20)
            assert snapshot("boxes-last")["pack"] == 16
            for _ in range(16):
                key(6)
                run(20)
            run(180)
            assert telemetry()["pack"] == 0
            key(8)
            assert snapshot("level-select")["view"] == 4
            report.update(passed=True, menuChecks=True, seconds=time.monotonic() - start,
                          audioFrames=audioframes, nonzeroAudioFrames=audiononzero)
            (directory / "menureport.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
            print("PASS: original-layout frontend, title, 17 boxes, locked packs, swipe/arrows, settings, audio, language fonts, credits, reset cancel, level selection")
            return
        key(8)
        key(8)
        if args.startup:
            buttons.add(8); run(3); buttons.clear(); run(1)
        else:
            key(8)
        if args.startup:
            sequence, clocks, strips = [], [], []
            for _ in range(600):
                run(1)
                state = telemetry()
                screen = framebuffer().crop((0,192,256,384))
                sequence.append(screen)
                clocks.append(state)
                if not state["transition"] and not state["door"] and state["ticks"] > 40:
                    strips.append((len(sequence)-1,screen.crop((0,25,30,150))))
            assert len(strips) > 120
            reference_strip = strips[-1][1]
            differences = [(index,sum(sum(p) for p in ImageChops.difference(strip,reference_strip).getdata()) / (30*125*3)) for index,strip in strips]
            worst = max(differences,key=lambda item:item[1])
            incoming = [row for row in clocks if 15 <= row["fadephase"] <= 27]
            assert len(incoming) >= 5 and incoming[-1]["ticks"] > incoming[0]["ticks"] + 3, "Physics froze during the incoming fade"
            assert abs(incoming[-1]["y"] - incoming[0]["y"]) > .01, "Candy stayed fixed during the incoming fade"
            sequence[0].save(directory / "level-startup.gif",save_all=True,append_images=sequence[1:],duration=17,loop=0)
            sequence[worst[0]].save(directory / "startup-worst-game.png")
            report.update(passed=worst[1] < 1,startupFrames=len(sequence),backgroundChange=worst[1],clocks=clocks,seconds=time.monotonic()-start)
            (directory / "startupreport.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
            assert worst[1] < 1, ("Texture upload corrupted the unchanged background",worst)
            print("PASS: physics/candy advance during incoming fade; 600 startup frames without background flashes")
            return
        run(180)
        idle = snapshot("idle")
        assert idle["magic"] == 0x44585250 and idle["state"] == 0 and idle["frames"] > 150, idle
        assert len(samples) == len(reference), samples
        errors = [math.hypot(samples[tick]["x"] - point["x"], samples[tick]["y"] - point["y"]) for tick, point in reference.items()]
        report["maximumDesktopError"] = max(errors)
        assert max(errors) < .05, errors
        candy = framebuffer().crop((119, 192 + 60, 137, 192 + 77))
        red = sum(r > 120 and r > g * 1.6 and r > b * 1.5 for r, g, b in candy.getdata())
        assert red >= 12, f"Candy pinwheel layer missing: only {red} red pixels"
        report["candyRedPixels"] = red
        if args.flow:
            sequence = []
            touch(100, 40)
            touch(155, 40)
            touch(155, 40, False)
            for _ in range(240):
                if telemetry()["view"] == 2:
                    break
                run(1)
            assert telemetry()["view"] == 2 and telemetry()["stars"] == 3
            assert not telemetry()["improved"], "First completion must not show an improvement stamp"
            resultvisuals = telemetry()["visuals"]
            resultframes = telemetry()["frames"]
            for i in range(1800):
                run(1)
                if i % 3 == 0:
                    sequence.append(framebuffer().crop((0, 192, 256, 384)))
                if i in (0, 15, 31, 55, 94, 135, 181, 225, 270, 360):
                    capture("result-phase-" + str(i))
                if telemetry()["frames"] >= resultframes + 365:
                    break
            elapsedframes = telemetry()["frames"] - resultframes
            assert elapsedframes >= 365 and telemetry()["visuals"] - resultvisuals == elapsedframes, ("Result transition froze world animation", telemetry())
            sequence[0].save(directory / "result-sequence.gif", save_all=True, append_images=sequence[1:], duration=48, loop=0)
            snapshot("result-complete")
            replay = []
            touch(98, 125)
            touch(98, 125, False)
            for i in range(60):
                run(1)
                replay.append(framebuffer().crop((0, 192, 256, 384)))
            replay[0].save(directory / "result-replay.gif", save_all=True, append_images=replay[1:], duration=16, loop=0)
            strip = Image.new("RGB", (256 * 10, 192 * 6))
            for i, item in enumerate(replay): strip.paste(item, (i % 10 * 256, i // 10 * 192))
            strip.save(directory / "replay-frames.png")
            settle()
            run(35)
            touch(100, 40)
            touch(155, 40)
            touch(155, 40, False)
            run(430)
            improved = snapshot("result-improved")
            assert improved["view"] == 2 and improved["improved"] == 1
            tap(98, 125)
            settle()
            key(3)
            assert snapshot("source-pause")["view"] == 1
            touch(128, 96)
            touch(128, 96, False)
            closing = []
            for _ in range(80):
                run(1)
                closing.append(framebuffer().crop((0, 192, 256, 384)))
            closing[0].save(directory / "box-quit.gif", save_all=True, append_images=closing[1:], duration=16, loop=0)
            assert snapshot("quit-levels")["view"] == 4
            touch(66, 26)
            touch(66, 26, False)
            opening = []
            openingclocks = {}
            for _ in range(95):
                run(1)
                opening.append(framebuffer().crop((0, 192, 256, 384)))
                current = telemetry()
                if not current["transition"] and current["door"] == 1:
                    openingclocks[current["frames"]] = current["visuals"]
                if _ in (28, 44, 60, 76):
                    capture("opening-" + str(_))
            opening[0].save(directory / "box-opening.gif", save_all=True, append_images=opening[1:], duration=16, loop=0)
            assert snapshot("opened-level")["view"] == 0
            # Texture uploads may consume VBlanks. Compare actual main-loop
            # frames while the flaps move, not an assumed 95 emu frames == 95 ticks.
            clocks = list(openingclocks.values())
            assert len(clocks) >= 10 and all(b > a for a,b in zip(clocks,clocks[1:])), "Opening flaps blocked world animation"
            report.update(passed=True, seconds=time.monotonic() - start)
            (directory / "flowreport.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
            print("PASS: complete result timeline, improvement-only stamp, replay, original pause, box close/open")
            return
        animation[0].save(directory / "animation.gif", save_all=True, append_images=animation[1:], duration=50, loop=0)
        strip = Image.new("RGB", (48 * 19, 64))
        for index, image in enumerate(animation[:19]):
            strip.paste(image.crop((104, 148, 152, 192)), (index * 48, 20))
            strip.paste(image.crop((104, 81, 152, 101)), (index * 48, 0))
        strip.save(directory / "animation-strip.png")
        if not args.inspect:
            run(args.soak)
            soak = snapshot("soak")
            assert soak["state"] == 0 and soak["stars"] == 0 and soak["late"] == idle["late"], soak
            touch(180, 150)
            touch(180, 130)
            touch(180, 130, False)
            assert telemetry()["cuts"] == 0, "A non-intersecting gesture cut the rope"
            touch(100, 40)
            for x in range(105, 156, 5):
                touch(x, 40)
            touch(155, 40, False)
            run(180)
            won = snapshot("win")
            assert won["state"] == 1 and won["stars"] == 3 and won["cuts"] == 1 and won["view"] == 2, won
            assert won["beststars"] == 3 and won["bestscore"] == won["score"] >= 3000, won
            settle()  # Result controls intentionally ignore input until flaps close.
            while telemetry()["menuage"] < 32: run(1)
            key(8)  # libretro joypad A
            run(70)
            retry = snapshot("retry")
            assert retry["state"] == 0 and retry["stars"] == 0 and retry["resets"] == 2, retry
            buttons.add(3)  # Start
            run(3)
            buttons.clear()
            beforepause = telemetry()
            run(60)
            paused = snapshot("paused")
            assert paused["paused"] == 1 and paused["ticks"] == beforepause["ticks"], paused
            touch(128,72); touch(40,72); touch(40,72,False)
            assert telemetry()["view"] == 1 and telemetry()["ticks"] == paused["ticks"], "Cancelled skip resumed gameplay"
            tap(104, 145)
            tap(152, 145)
            quiet = snapshot("quiet")
            assert quiet["effects"] == 0 and quiet["music"] == 0, quiet
            run(60)
            silence = audiononzero
            run(60)
            assert audiononzero == silence, "Audio persisted with both toggles off"
            buttons.add(3)
            run(3)
            buttons.clear()
            run(30)
            resumed = snapshot("resumed")
            assert resumed["paused"] == 0 and resumed["ticks"] > paused["ticks"], resumed
            tap(220, 8)
            touchretry = snapshot("touchretry")
            assert touchretry["resets"] == 3 and touchretry["ticks"] < resumed["ticks"], touchretry
            touch(241, 8)
            touch(100, 40)
            touch(155, 40)
            touch(155, 40, False)
            assert telemetry()["view"] == 0 and telemetry()["cuts"] == 1, "Cancelled HUD drag leaked into gameplay"
            tap(241, 8)
            assert telemetry()["view"] == 1, "Touch pause failed"
            tap(128, 96)
            settle()
            levels = snapshot("levels")
            assert levels["view"] == 4 and levels["beststars"] == 3, levels
            key(0)
            assert telemetry()["view"] == 6
            key(0)
            home = snapshot("home")
            assert home["view"] == 5, home
            tap(128, 170)
            tap(104, 28)
            tap(152, 28)
            beforemusic = audiononzero
            run(60)
            assert telemetry()["effects"] == 1 and telemetry()["music"] == 1 and audiononzero > beforemusic
            key(0)
            key(8)
            assert telemetry()["view"] == 6
            key(8)
            assert telemetry()["view"] == 4
            key(8)
            assert telemetry()["view"] == 0 and telemetry()["resets"] == 4
            settle()
            run(60)
            touch(100, 40)
            touch(155, 40)
            touch(155, 40, False)
            run(200)
            fastwin = snapshot("fastwin")
            assert fastwin["view"] == 2 and fastwin["score"] > 5000 and fastwin["bestscore"] == fastwin["score"], fastwin
            while telemetry()["menuage"] < 32: run(1)
            settle(); tap(98,125); settle(); tap(241,8)
            before = telemetry()
            tap(128,72)
            skipped = snapshot("pause-skip")
            assert skipped["view"] == 0 and skipped["level"] == 1 and skipped["resets"] == before["resets"]+1 and not skipped["door"] and not skipped["flash"], skipped
            final = snapshot("complete")
            assert final["late"] >= idle["late"], final
            assert final["vblanks"] - idle["vblanks"] == final["frames"] - idle["frames"] + final["late"] - idle["late"], "Unaccounted VBlanks"
            assert touchretry["vblanks"] - idle["vblanks"] == touchretry["frames"] - idle["frames"] + touchretry["late"] - idle["late"], "Unaccounted scene-loading VBlanks"
            assert audiononzero > 0, "No sound effects reached the audio callback"
        report.update(seconds=time.monotonic() - start, audioFrames=audioframes, nonzeroAudioFrames=audiononzero)
        report["passed"] = True
        report["soakFrames"] = 0 if args.inspect else args.soak
        (directory / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(f"PASS: DS boot, {len(samples)} original trajectories (max error {max(errors):.6f}), "
              f"{report['soakFrames']} soak frames" + ("" if args.inspect else ", candy layers, HUD, swipe, win/score, retry, pause, audio toggles, menu navigation, no input leakage"), flush=True)
    finally:
        try:
            if profiler:
                profiler.save()
        finally:
            if loaded:
                core.retro_unload_game()
            core.retro_deinit()


if __name__ == "__main__":
    main()
