set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$DIR/../src/CutTheRopeDX.csproj"
CONFIG="Debug"; [ "${1:-}" = "release" ] && CONFIG="Release"

echo "building desktop $CONFIG.."
if [ "$CONFIG" = "Release" ]; then
  RID="${2:-linux-x64}"
  dotnet publish "$PROJ" -c Release -f net9.0 -r "$RID" -nodeReuse:false
  echo "done! at: $DIR/../bin/Release/net9.0/$RID/publish/"
else
  dotnet build "$PROJ" -c Debug -f net9.0 -nodeReuse:false
  echo "done! at: $DIR/../bin/Debug/net9.0/CutTheRope-DX (.exe on windows)"
fi
printf '\a'
