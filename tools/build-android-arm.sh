#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$DIR/../src/CutTheRopeDX.csproj"
CONFIG="Debug"; [ "${1:-}" = "release" ] && CONFIG="Release"

SDKARG=()
[ -n "${ANDROID_HOME:-}" ] && SDKARG=(-p:AndroidSdkDirectory="$ANDROID_HOME")

echo "building $CONFIG.."
dotnet build "$PROJ" -c "$CONFIG" \
  -p:CtrAndroidOnly=true "${SDKARG[@]}" \
  -p:EmbedAssembliesIntoApk=true \
  -p:DebugSymbols=false -p:DebugType=none \
  -p:AndroidPackageFormat=apk -p:RunAOTCompilation=false -nodeReuse:false

apk="$(find "$DIR/../bin/$CONFIG/net9.0-android" -name '*-Signed.apk' 2>/dev/null | head -1)"
if [ -n "$apk" ]; then
  cp -f "$apk" "$DIR/../bin/CutTheRope-DX-arm.apk"
  echo "done! at: $DIR/../bin/CutTheRope-DX-arm.apk"
else
  echo "build finished but no signed apk found?!" >&2
fi
printf '\a'
