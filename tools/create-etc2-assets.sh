#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PY=python3; command -v python3 >/dev/null 2>&1 || PY=python
if ! command -v "$PY" >/dev/null 2>&1; then
  echo "python 3 not found - install it (e.g. 'brew install python' / 'apt install python3')." >&2
  exit 1
fi

echo "installing python packages.."
"$PY" -m pip install --quiet --upgrade etcpak pillow numpy

echo "encoding textures.."
"$PY" "$DIR/create etc2 assets.py"

echo "building sound effects.."
dotnet tool restore
( cd "$DIR/../assets" && dotnet mgcb /@:content-android.mgcb )

echo "assets generated!"
printf '\a'
