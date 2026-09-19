# Platform layout

The C# game is divided into a platform-neutral runtime and small host projects.
Roblox is maintained as a source-faithful port because Roblox cannot execute the
.NET assemblies.

## Shared C# runtime

- `src/CutTheRopeDX.Core` owns gameplay, scene flow, content contracts, and
  platform service interfaces.
- `src/CutTheRopeDX.Rendering.Skia` owns the reusable Skia renderer.
- Desktop, Browser, and Android hosts compose those projects with their own
  input, lifecycle, storage, media, and window implementations.

## Android

The active Android host belongs in `src/CutTheRopeDX.Android`. The old private
MonoGame fork is preserved by merge commit `3a41383e`; small files that are
useful while translating it are retained in `ports/android-legacy`.

The Android migration order is:

1. Create a `net10.0-android` host referencing Core and Rendering.Skia.
2. Implement the Android surface and game loop without adding Android branches
   to Core.
3. Add touch, lifecycle, immersive mode, safe-area, preference, audio, video,
   and document-picker adapters.
4. Package canonical `content` through an Android-specific build target.
5. Review the four retained custom asset groups and register only the assets
   that are intended to be part of the shared game.
6. Add APK and AAB CI after device and emulator smoke tests pass.

The Browser single-threaded build remains a possible WebView fallback, but it
is not the native host architecture.

## Roblox

- `ports/roblox/src` contains authored Luau arranged by Roblox service.
- `ports/roblox/tests` contains Luau checks and C#-generated golden data.
- `ports/roblox/generated` contains intermediate atlases, manifests, and trace
  output.
- `tools/roblox` contains importers, exporters, and conformance tooling.

Canonical levels, localization, sprite metadata, and behavior traces always
come from the root C# and `content` trees. Generated Luau should be reproducible
and should not become a second hand-edited source of truth.

Roblox fidelity is checked by exporting deterministic traces from the C# test
project and comparing them with Luau results. Platform-specific rendering,
input, audio, persistence, and networking remain authored Luau adapters.
