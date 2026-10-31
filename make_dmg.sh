#!/bin/zsh
set -euo pipefail

APP_NAME="MenuBarCalendar"
APP_DIR="dist/${APP_NAME}.app"
DMG_NAME="${APP_NAME}"

if [[ ! -d "$APP_DIR" ]]; then
  echo "Error: ${APP_DIR} not found. Run ./build_app.sh first." >&2
  exit 1
fi

VERSION="${1:-}"
if [[ -n "$VERSION" ]]; then
  DMG_NAME="${APP_NAME}-${VERSION}"
fi

rm -f "dist/${DMG_NAME}.dmg"

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "$APP_DIR" \
  -ov \
  -format UDZO \
  "dist/${DMG_NAME}.dmg"

echo "Created dist/${DMG_NAME}.dmg"
echo "Note: unsigned DMG — recipients need to right-click > Open on first launch."
