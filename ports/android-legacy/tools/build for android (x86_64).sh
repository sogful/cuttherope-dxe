#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$DIR/../src/CutTheRopeDX.csproj"
OUT="$DIR/bin/CutTheRope-DX-x86_64.apk"
CONFIG="Debug"; [ "${1:-}" = "release" ] && CONFIG="Release"

SDKARG=()
[ -n "${ANDROID_HOME:-}" ] && SDKARG=(-p:AndroidSdkDirectory="$ANDROID_HOME")

echo "building $CONFIG.."
dotnet build "$PROJ" -c "$CONFIG" \
  -p:CtrAndroidOnly=true "${SDKARG[@]}" \
  -p:RuntimeIdentifier=android-x64 \
  -p:EmbedAssembliesIntoApk=true \
  -p:DebugSymbols=false -p:DebugType=none \
  -p:AndroidPackageFormat=apk -p:RunAOTCompilation=false -nodeReuse:false

apk="$(find "$DIR/bin/$CONFIG/net9.0-android/android-x64" -name '*-Signed.apk' 2>/dev/null | head -1)"
if [ -n "$apk" ]; then
  cp -f "$apk" "$OUT"
  echo "done! at: $OUT"
else
  echo "build finished but no signed apk found?!" >&2
fi
printf '\a'

if [ -f "$OUT" ]; then
  read -r -p "open the apk now? (y/n): " ans || ans=""
  if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
    if command -v xdg-open >/dev/null 2>&1; then xdg-open "$OUT" >/dev/null 2>&1 &
    elif command -v open >/dev/null 2>&1; then open "$OUT"; fi
  fi
fi
