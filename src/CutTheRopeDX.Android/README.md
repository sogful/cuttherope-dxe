# CutTheRopeDX.Android

This directory is reserved for the native `net10.0-android` host.

The host will reference `CutTheRopeDX.Core` and
`CutTheRopeDX.Rendering.Skia`, then provide Android implementations for the
platform services composed by the Desktop and Browser entry points. It must not
copy the old MonoGame game runtime or add Android conditionals to Core.

See `PORTS.md` and `ports/android-legacy` for the migration order and retained
reference files.
