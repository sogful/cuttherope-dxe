<p align="center">
  <img src="./ports/ds/assets/logods.png" width="256"/>
</p>

*Cut the Rope: DXfDS (Decompiled Extra for Dual Screen)* is an NDS C++ port that fits in *<4mb of main RAM*, it also runs in DSi mode.

#### features

- upper screen with a view of the level above, along with stars & score
- an "unlock all" option in settings. turning this on switches the game to a separate save profile to not ruin your real progress for the main game.
- progress and settings in `/ctrdx/` (on writable homebrew storage)

#### building

the build scripts are for windows *(also requires python 3.12 and 7-zip to be installed)*, .NET 10 SDK is also needed for the costume animation exporter..

1. clone the repository and install the asset convert dependencies:

    ```powershell
    git clone https://github.com/sogful/cuttherope-dxe.git
    cd cuttherope-dxe
    python -m pip install -r ports/ds/tools/requirements.txt
    ```

2. install the blocksds toolchain, then build:

    ```powershell
    powershell -ExecutionPolicy Bypass -File ports/ds/tools/setup.ps1
    python ports/ds/tools/build.py --assets
    ```
