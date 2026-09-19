# Cut the Rope DX - Nintendo DS feasibility slice

A native C++/BlocksDS slice of Cardboard Box **1-1**, targeting the original DS in DS mode. No .NET runtime, Roblox runtime, external BIOS files, DSi-only memory, or downloaded game assets are needed.

This is a working one-level prototype, not a complete port. The purpose is to test the original physics, original assets, stylus input, animation, sound, and frame budget on the weaker target before expanding the game.

## Play

Open [`dist/cuttherope.nds`](dist/cuttherope.nds) in melonDS, or use a suitable homebrew loader on a DS/DSi. Physical hardware has not been tested yet.

The game uses a sideways, book-style layout. Rotate the emulator display 90 degrees clockwise, or hold the handheld with the touch screen on the left. The complete level is on the touch screen; the other screen contains instructions and diagnostics.

- Swipe across the rope to cut it. Collect the three stars and feed Om Nom.
- Press **A**, or tap **RETRY**, to restart.
- Press **START** to pause/resume. Touch anywhere after winning to restart.

The ROM includes sound effects. Automated tests discard audio instead of sending it to an output device. Music, menus, saves, level selection, additional boxes/mechanics, localization, and the complete DX presentation are not implemented.

## Build on Windows

Prerequisites: Python **3.12**, PowerShell, 7-Zip installed at its standard location, and network access for the first toolchain installation. Run from the repository root:

```powershell
python -m pip install -r ports/ds/tools/requirements.txt
powershell -ExecutionPolicy Bypass -File ports/ds/tools/setup.ps1
python ports/ds/tools/build.py --assets
```

The setup installs portable MSYS2, Wonderful Toolchain, and BlocksDS inside `ports/ds/.tools`. It does not require WSL or a system-wide compiler installation. Downloads, generated assets, object files, and ROMs are gitignored. Subsequent source-only builds can omit `--assets`.

The packer explicitly sets `-uc 0` for a DS-only header. Leaving the current toolchain's default header caused emulators to classify this build as DSiWare.

## Test without a visible window or sound

```powershell
powershell -ExecutionPolicy Bypass -File ports/ds/tools/setup-emulator.ps1
python ports/ds/tools/headless.py
```

This uses the [melonDS DS libretro core](https://github.com/JesseTG/melonds-ds) with software rendering and built-in replacement BIOS/firmware. It creates **no window**, uses no microphone, discards output audio, and runs entirely in the test process. Your existing melonDS installation and settings are untouched. Standalone melonDS's hidden-desktop startup was unreliable on the development machine, so it is not the validation backend.

The test checks actual ROM memory and injects emulated stylus/button input, not game-side test commands. It asserts:

- DS boot and all nine original DX reference trajectory samples.
- 3,600 additional idle frames without missed VBlanks.
- A missed gesture leaves the rope intact; a crossing gesture cuts once.
- Three stars, a win, button retry, touch retry, pause, and resume.
- Non-silent sound-effect samples reach the discarded audio callback.

Outputs are in `build/headless`: JSON evidence, raw dual-screen captures, and clockwise-rotated `*-portrait.png` previews. `--inspect` performs boot/trajectory checks only; `--soak N` controls the extra stability frames. The report includes the exact core and ROM SHA-256 hashes.

For independent host-side physics tests, install a native `g++` on PATH, then run:

```powershell
python ports/ds/tools/test.py
```

These also cover delayed detachment, zero-length/duplicate cuts, terminal-state freezing, reset, early-cut winning, loss, and long-run finite coordinates. A tiny boot-only compatibility probe is available through `python ports/ds/tools/build.py --bootcheck`.

## Measured result

Validated with BlocksDS 1.23.0 and melonDS DS 1.3.1, in **DS mode**, on 2026-09-19:

| Measure | Result |
| --- | --- |
| ROM | 861,280 bytes, about 841 KiB |
| ARM9 ELF text + data + BSS | 807,728 bytes; excludes stack, heap, and ARM7 |
| Main-screen textures | 384 KiB: A3I5 sprite atlas + direct-color background |
| Secondary-screen bitmap | 128 KiB |
| Converted sound effects | 173,100 bytes, mono PCM16 at 16 kHz |
| Active update/render CPU time | About 6.3 ms; observed peak 9.547 ms including diagnostic-panel refresh |
| Gameplay frames observed | 4,152, including the extra 3,600-frame stability run |
| Missed VBlanks | 0 |
| Maximum trajectory error | 0.000046 DX pixels, both host and emulated ARM builds |

Timing comes from DS hardware timers in the emulated ROM, not the host machine's playback speed. It measures input, simulation, sound submission, drawing command submission, and periodic diagnostic rendering; it is **not** a separate GPU completion measurement. The VBlank/frame counters independently check whether the main loop keeps up. This supports a roughly 60 Hz first-level slice, not a performance guarantee for every DX level or real hardware.

The next useful performance gate is a representative multi-rope level plus one extra mechanic. Keep the floating-point reference solver until that benchmark demonstrates where optimization is necessary. The 192x256 portrait crop also needs a camera/layout policy for wider levels.

## Source fidelity and boundaries

- `source/simulation.cpp` follows `src/CutTheRopeDX.Core/Framework/Physics/ConstraintedPoint.cs`, `GameMain/Bungee.cs`, `GameMain/GameScene.Update.cs`, and `GameMain/LoadObjects/LoadTarget.cs`. It retains the 0.016-second step, rope speed multiplier, solver order, 30 constraint iterations, and delayed cut behavior used by this level.
- `tools/assets.py` reads `content/maps/1_1.xml` and existing atlas JSON/PNG, font, and WAV files. Quad indices, trim offsets, source canvas sizes, and rotations are explicit. No substitute artwork is generated. Source hashes and quad mappings are recorded in `generated/manifest.json`.
- Reference trajectories come from the existing `ports/roblox/tests/desktop-trajectories.json`, captured from the original DX implementation, not from a generic rope simulation.
- Pools are sized for the slice, with eight ropes and 256 bodies reserved. The converter intentionally imports only 1-1; these capacities do not imply arbitrary-level support or measured multi-rope performance.
- Animation, rope drawing, feedback, collision coverage, and layout implement the subset needed for this level. They are not a claim of full DX parity.

Toolchain setup follows the [BlocksDS Windows instructions](https://blocksds.skylyrac.net/docs/setup/windows/) and [Wonderful bootstrap instructions](https://wonderful.asie.pl/wiki/doku.php?id=getting_started:windows). Original game asset rights remain unchanged; generated ROMs and converted assets are local build outputs, not relicensed content.
