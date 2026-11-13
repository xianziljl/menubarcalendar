#!/bin/zsh
set -euo pipefail

# Usage: scripts/make_icon.sh <path-to-square-source.png>
# Generates Resources/AppIcon.icns from a single source image.

# Anchor to the repo root so relative Resources/ paths work from anywhere.
cd "${0:A:h}/.." || exit 1

SRC="${1:-}"
if [[ -z "$SRC" || ! -f "$SRC" ]]; then
  echo "Usage: scripts/make_icon.sh <path-to-square-source.png>" >&2
  exit 1
fi

TMPDIR_ICON="$(mktemp -d)"
ICONSET_DIR="${TMPDIR_ICON}/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

# Verify source is square
WIDTH=$(sips -g pixelWidth "$SRC" | awk '/pixelWidth/{print $2}')
HEIGHT=$(sips -g pixelHeight "$SRC" | awk '/pixelHeight/{print $2}')
if [[ "$WIDTH" != "$HEIGHT" ]]; then
  echo "Error: source image must be square (got ${WIDTH}x${HEIGHT})." >&2
  exit 1
fi

# All required macOS icon sizes from a single source
for size in 16 32 128 256 512; do
  sips -z $size $size "$SRC" --out "${ICONSET_DIR}/icon_${size}x${size}.png" >/dev/null
done
sips -z 32 32   "$SRC" --out "${ICONSET_DIR}/icon_16x16@2x.png"   >/dev/null
sips -z 64 64   "$SRC" --out "${ICONSET_DIR}/icon_32x32@2x.png"   >/dev/null
sips -z 256 256 "$SRC" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
sips -z 512 512 "$SRC" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
sips -z 1024 1024 "$SRC" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null

mkdir -p Resources
iconutil -c icns "$ICONSET_DIR" -o "Resources/AppIcon.icns"

echo "Created Resources/AppIcon.icns — rebuilt .app will include it automatically."
