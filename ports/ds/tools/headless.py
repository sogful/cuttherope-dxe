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
    parser.add_argument("--soak", type=int, default=3600, help="Additional idle frames before interaction tests")
    args = parser.parse_args()
    core = c.CDLL(args.core)
    directory = root / "build/headless"
    directory.mkdir(parents=True, exist_ok=True)
    folder = str(directory).encode()
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
            return write(data, c.c_char_p, folder)
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
        keys = ["magic", "version", "frames", "ticks", "state", "stars", "micros", "peak", "late", "vblanks", "x", "y", "cuts", "touches", "resets", "paused"]
        memory = core.retro_get_memory_data(2)
        size = core.retro_get_memory_size(2)
        offset = address - 0x02000000
        if not memory or offset + 64 > size:
            raise RuntimeError(f"Cannot read telemetry: RAM={size} address={address:x}")
        assert size == 4 * 1024 * 1024, f"Expected original DS main RAM, received {size} bytes"
        report["mainRamBytes"] = size
        references = json.loads((root.parent / "roblox/tests/desktop-trajectories.json").read_text())
        reference = {sample["tick"]: sample for trace in references if trace["level"] == 1 for sample in trace["samples"]}
        samples = {}
        def telemetry():
            return dict(zip(keys, struct.unpack("<10I2f4I", c.string_at(memory + offset, 64))))
        def run(count):
            for _ in range(count):
                core.retro_run()
                current = telemetry()
                tick = current["ticks"]
                if tick in reference and tick not in samples and current["resets"] == 0:
                    samples[tick] = current
                if current["resets"] == 0 and 10 <= tick < 124 and tick % 3 == 1:
                    animation.append(framebuffer().crop((0, 192, 256, 384)))
        def snapshot(label):
            result = telemetry()
            report["stages"][label] = result
            print(label, result, flush=True)
            capture(label)
            return result
        start = time.monotonic()
        run(180)
        idle = snapshot("idle")
        assert idle["magic"] == 0x44585250 and idle["state"] == 0 and idle["frames"] > 150, idle
        assert len(samples) == len(reference), samples
        errors = [math.hypot(samples[tick]["x"] - point["x"], samples[tick]["y"] - point["y"]) for tick, point in reference.items()]
        report["maximumDesktopError"] = max(errors)
        assert max(errors) < .05, errors
        animation[0].save(directory / "animation.gif", save_all=True, append_images=animation[1:], duration=50, loop=0)
        strip = Image.new("RGB", (48 * 19, 64))
        for index, image in enumerate(animation[:19]):
            strip.paste(image.crop((104, 148, 152, 192)), (index * 48, 20))
            strip.paste(image.crop((104, 81, 152, 101)), (index * 48, 0))
        strip.save(directory / "animation-strip.png")
        if not args.inspect:
            run(args.soak)
            soak = snapshot("soak")
            assert soak["state"] == 0 and soak["stars"] == 0 and soak["late"] == 0, soak
            # Absolute pointer coordinates refer to the whole 256x384 dual-screen frame.
            def touch(x, y, held=True):
                pointer[:] = [round(x / 255 * 65534 - 32767), round((192 + y) / 383 * 65534 - 32767), int(held)]
                run(3)
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
            assert won["state"] == 1 and won["stars"] == 3 and won["cuts"] == 1, won
            buttons.add(8)  # libretro joypad A
            run(3)
            buttons.clear()
            run(30)
            retry = snapshot("retry")
            assert retry["state"] == 0 and retry["stars"] == 0 and retry["resets"] == 1, retry
            buttons.add(3)  # Start
            run(3)
            buttons.clear()
            beforepause = telemetry()
            run(60)
            paused = snapshot("paused")
            assert paused["paused"] == 1 and paused["ticks"] == beforepause["ticks"], paused
            buttons.add(3)
            run(3)
            buttons.clear()
            run(30)
            resumed = snapshot("resumed")
            assert resumed["paused"] == 0 and resumed["ticks"] > paused["ticks"], resumed
            touch(225, 10)
            touch(225, 10, False)
            touchretry = snapshot("touchretry")
            assert touchretry["resets"] == 2 and touchretry["ticks"] < resumed["ticks"], touchretry
            assert touchretry["late"] == 0, touchretry
            assert touchretry["vblanks"] - idle["vblanks"] == touchretry["frames"] - idle["frames"], "Game loop lost VBlanks"
            assert audiononzero > 0, "No sound effects reached the audio callback"
        report.update(seconds=time.monotonic() - start, audioFrames=audioframes, nonzeroAudioFrames=audiononzero)
        report["passed"] = True
        report["soakFrames"] = 0 if args.inspect else args.soak
        (directory / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(f"PASS: DS boot, {len(samples)} original trajectories (max error {max(errors):.6f}), "
              f"{report['soakFrames']} soak frames" + ("" if args.inspect else ", swipe, stars, win, retry, pause/resume, sound"), flush=True)
    finally:
        if loaded:
            core.retro_unload_game()
        core.retro_deinit()


if __name__ == "__main__":
    main()
