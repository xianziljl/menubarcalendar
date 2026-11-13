#!/bin/zsh
set -euo pipefail

APP_NAME="MenuBarCalendar"
CONFIGURATION="release"

source "${0:A:h}/bundle-common.sh"

resolve_version "${1:-}"

# --- Signing ---------------------------------------------------------------------
# Default: ad-hoc ("-") with entitlements — sandbox enabled, works locally.
# Distribution: SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ./scripts/build_app.sh
#               (adds --options runtime --timestamp automatically)
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

build_universal_binary
assemble_bundle
compile_icon_assets
write_plist_and_resources

# --- Codesign ----------------------------------------------------------------------
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - --entitlements "$ENTITLEMENTS_FILE" "$APP_DIR"
else
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS_FILE" "$APP_DIR"
fi

echo "Built ${APP_DIR} (v${APP_VERSION} build ${BUILD_NUMBER}, universal, sandboxed)"
