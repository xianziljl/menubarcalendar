#!/bin/zsh
set -euo pipefail

APP_NAME="MenuBarCalendar"
CONFIGURATION="release"
BUILD_DIR=".build"
APP_DIR="dist/${APP_NAME}.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"

# --- Version -------------------------------------------------------------------
# Priority: $1 arg > APP_VERSION env > latest git tag > "1.0.0"
APP_VERSION="${1:-${APP_VERSION:-}}"
if [[ -z "$APP_VERSION" ]]; then
  APP_VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
fi
APP_VERSION="${APP_VERSION:-1.0.0}"

BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

# --- Signing ---------------------------------------------------------------------
# Default: ad-hoc ("-") with entitlements — sandbox enabled, works locally.
# Distribution: SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" ./build_app.sh
#               (adds --options runtime --timestamp automatically)
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ENTITLEMENTS_FILE="MenuBarCalendar.entitlements"

# --- Universal build (arm64 + x86_64) ---------------------------------------------
swift build -c "$CONFIGURATION" --arch arm64 --arch x86_64

# Universal products land in .build/apple/Products/<Config>/
BINARY_PATH="${BUILD_DIR}/apple/Products/${CONFIGURATION}/${APP_NAME}"
if [[ ! -f "$BINARY_PATH" ]]; then
  # Fallback for toolchains without universal support
  BINARY_PATH="${BUILD_DIR}/${CONFIGURATION}/${APP_NAME}"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"

# --- Icon (optional until provided) ------------------------------------------------
if [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
else
  echo "Warning: Resources/AppIcon.icns not found — app will have no icon."
  echo "         Run ./make_icon.sh <1024x1024.png> to generate one."
fi

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
    </array>
    <key>CFBundleExecutable</key>
    <string>MenuBarCalendar</string>
    <key>CFBundleIdentifier</key>
    <string>com.zhuxianyong.menubarcalendar</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MenuBarCalendar</string>
    <key>CFBundleDisplayName</key>
    <string>Menubar Calendar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSCalendarsUsageDescription</key>
    <string>需要访问日历以在菜单栏面板中显示选中日期的日程。</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>需要完整访问日历以显示选中日期的日程。</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026. All rights reserved.</string>
</dict>
</plist>
PLIST

printf 'APPL????\n' > "${APP_DIR}/Contents/PkgInfo"

ditto "Resources/en.lproj" "${RESOURCES_DIR}/en.lproj"
ditto "Resources/zh-Hans.lproj" "${RESOURCES_DIR}/zh-Hans.lproj"

# --- Codesign ----------------------------------------------------------------------
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - --entitlements "$ENTITLEMENTS_FILE" "$APP_DIR"
else
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS_FILE" "$APP_DIR"
fi

echo "Built ${APP_DIR} (v${APP_VERSION} build ${BUILD_NUMBER}, universal, sandboxed)"
