#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$DIR/../src/CutTheRopeDX.csproj"
CONFIG="Debug"; [ "${1:-}" = "release" ] && CONFIG="Release"

echo "building desktop $CONFIG.."
if [ "$CONFIG" = "Release" ]; then
  RID="${2:-linux-x64}"
  dotnet publish "$PROJ" -c Release -f net9.0 -r "$RID" -nodeReuse:false
  OUT="$DIR/bin/Release/net9.0/$RID/publish/CutTheRope-DX"
else
  dotnet build "$PROJ" -c Debug -f net9.0 -nodeReuse:false
  OUT="$DIR/bin/Debug/net9.0/CutTheRope-DX"
fi
[ -f "$OUT.exe" ] && OUT="$OUT.exe"
echo "done! at: $OUT"
printf '\a'

if [ -f "$OUT" ]; then
  read -r -p "open the build now? (y/n): " ans || ans=""
  if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
    "$OUT" &
  fi
fi
