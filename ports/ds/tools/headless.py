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
    parser.add_argument("--soak", type=int, default=3600, help="Additional idle frames before interaction tests")
    args = parser.parse_args()
    core = c.CDLL(args.core)
    directory = root / "build/headless"
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
        symbols = (root / "build/symbols.txt").read_text().splitlines()
        address = int(next(line.split()[0] for line in symbols if line.endswith(" telemetry")), 16)
        report = {"core": str(Path(args.core).resolve()), "coreSha256": hashlib.sha256(Path(args.core).read_bytes()).hexdigest(),
                  "romSha256": hashlib.sha256(path.read_bytes()).hexdigest(), "console": "DS", "muted": True, "headless": True, "stages": {}}
        keys = ["magic", "version", "frames", "ticks", "state", "stars", "micros", "peak", "late", "vblanks", "x", "y", "cuts", "touches", "resets", "paused",
                "view", "effects", "music", "score", "bestscore", "beststars", "locale", "pack", "clickcut", "scroll", "texturebytes",
                "unlocked", "skintab", "candy", "rope", "costume", "trace", "skinoffset", "transition", "storage", "door", "doorframe", "menuage", "improved"]
        memory = core.retro_get_memory_data(2)
        size = core.retro_get_memory_size(2)
        offset = address - 0x02000000
        if not memory or offset + 160 > size:
            raise RuntimeError(f"Cannot read telemetry: RAM={size} address={address:x}")
        assert size == 4 * 1024 * 1024, f"Expected original DS main RAM, received {size} bytes"
        report["mainRamBytes"] = size
        references = json.loads((root.parent / "roblox/tests/desktop-trajectories.json").read_text())
        reference = {sample["tick"]: sample for trace in references if trace["level"] == 1 for sample in trace["samples"]}
        samples = {}
        referenceattempt = 1
        lastframe, stalled = -1, 0
        def telemetry():
            return dict(zip(keys, struct.unpack("<10I2f28I", c.string_at(memory + offset, 160))))
        def run(count):
            nonlocal lastframe, stalled
            for _ in range(count):
                core.retro_run()
                current = telemetry()
                stalled = stalled + 1 if current["frames"] == lastframe else 0
                lastframe = current["frames"]
                assert stalled < 120, "ROM main loop stalled (check emulator diagnostic output)"
                tick = current["ticks"]
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
            touch(x, y)
            touch(x, y, False)
            run(36)
        def key(ident):
            buttons.add(ident)
            run(3)
            buttons.clear()
            run(36)
        def settle():
            for _ in range(100):
                current = telemetry()
                if not current["door"] and not current["transition"]:
                    return
                run(1)
            raise AssertionError("Transition failed to finish")
        run(60)
        title = snapshot("title")
        assert title["view"] == 5 and title["ticks"] == 0 and title["frames"] > 40, title
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
            tap(66, 26)
            assert telemetry()["view"] == 4 and telemetry()["resets"] == 0, "An unavailable map silently launched 1-1"
            key(0)
            key(6)
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
        key(8)
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
            for i in range(365):
                run(1)
                if i % 3 == 0:
                    sequence.append(framebuffer().crop((0, 192, 256, 384)))
                if i in (0, 15, 31, 55, 94, 135, 181, 225, 270, 360):
                    capture("result-phase-" + str(i))
            sequence[0].save(directory / "result-sequence.gif", save_all=True, append_images=sequence[1:], duration=48, loop=0)
            snapshot("result-complete")
            tap(98, 125)
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
            for _ in range(95):
                run(1)
                opening.append(framebuffer().crop((0, 192, 256, 384)))
                if _ in (28, 44, 60, 76):
                    capture("opening-" + str(_))
            opening[0].save(directory / "box-opening.gif", save_all=True, append_images=opening[1:], duration=16, loop=0)
            assert snapshot("opened-level")["view"] == 0
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
            tap(158, 125)
            assert telemetry()["view"] == 2 and telemetry()["resets"] == 1, "Disabled next button changed the level"
            buttons.add(8)  # libretro joypad A
            run(3)
            buttons.clear()
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
            tap(128, 72)
            assert telemetry()["view"] == 1 and telemetry()["ticks"] == paused["ticks"], "Disabled skip resumed gameplay"
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
        if loaded:
            core.retro_unload_game()
        core.retro_deinit()


if __name__ == "__main__":
    main()
