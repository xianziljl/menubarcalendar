#!/bin/zsh
set -euo pipefail

APP_NAME="MenuBarCalendar"
CONFIGURATION="release"
BUILD_DIR=".build"
APP_DIR="dist/${APP_NAME}.app"
PKG_PATH="dist/${APP_NAME}.pkg"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"

# --- Version -------------------------------------------------------------------
APP_VERSION="${1:-${APP_VERSION:-}}"
if [[ -z "$APP_VERSION" ]]; then
  APP_VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
fi
APP_VERSION="${APP_VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

# --- Certificates for Mac App Store ---------------------------------------------
# Override by env, e.g. SIGN_APP_IDENTITY="Apple Distribution: xianyong zhu (7KURWGBJYX)"
SIGN_APP_IDENTITY="${SIGN_APP_IDENTITY:-Apple Distribution}"
SIGN_INSTALLER_IDENTITY="${SIGN_INSTALLER_IDENTITY:-3rd Party Mac Developer Installer}"
ENTITLEMENTS_FILE="MenuBarCalendar.entitlements"

echo "==> Universal build (arm64 + x86_64)"
swift build -c "$CONFIGURATION" --arch arm64 --arch x86_64

BINARY_PATH="${BUILD_DIR}/apple/Products/${CONFIGURATION}/${APP_NAME}"
if [[ ! -f "$BINARY_PATH" ]]; then
  BINARY_PATH="${BUILD_DIR}/${CONFIGURATION}/${APP_NAME}"
fi

echo "==> Assemble .app bundle"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY_PATH" "${MACOS_DIR}/${APP_NAME}"
strip -x "${MACOS_DIR}/${APP_NAME}"

# Icon
if [[ -d "icon.icon" ]]; then
  TMP_ICON="$(mktemp -d)"
  cp -R "icon.icon" "${TMP_ICON}/AppIcon.icon"
  mkdir -p "${TMP_ICON}/out"
  ACTOOL="$(xcrun -f actool)"
  "$ACTOOL" "${TMP_ICON}/AppIcon.icon" \
    --compile "${TMP_ICON}/out" \
    --platform macosx \
    --target-device mac \
    --minimum-deployment-target 12.0 \
    --app-icon AppIcon \
    --enable-on-demand-resources NO \
    --output-partial-info-plist "${TMP_ICON}/info.plist"
  cp "${TMP_ICON}/out/Assets.car" "${RESOURCES_DIR}/Assets.car"

  ICTOOL="/Applications/Icon Composer.app/Contents/Executables/ictool"
  if [[ -x "$ICTOOL" ]] && \
     "$ICTOOL" "${TMP_ICON}/AppIcon.icon" \
       --export-image --output-file "${TMP_ICON}/icon1024.png" \
       --platform macOS --rendition Default \
       --width 1024 --height 1024 --scale 1 >/dev/null 2>&1; then
    ./make_icon.sh "${TMP_ICON}/icon1024.png"
    cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
  else
    cp "${TMP_ICON}/out/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
  fi
  rm -rf "$TMP_ICON"
elif [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
else
  echo "Warning: Resources/AppIcon.icns not found — app will have no icon."
fi

# Info.plist
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
        <string>zh-Hant</string>
        <string>ja</string>
    </array>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.zhuxianyong.menubarcalendar</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
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
    <key>CFBundleIconName</key>
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
ditto "Resources/zh-Hant.lproj" "${RESOURCES_DIR}/zh-Hant.lproj"
ditto "Resources/ja.lproj" "${RESOURCES_DIR}/ja.lproj"

echo "==> Codesign .app with ${SIGN_APP_IDENTITY}"
codesign --force --sign "$SIGN_APP_IDENTITY" --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS_FILE" "$APP_DIR"

echo "==> Package .pkg with ${SIGN_INSTALLER_IDENTITY}"
rm -f "$PKG_PATH"
productbuild --component "$APP_DIR" /Applications \
  --sign "$SIGN_INSTALLER_IDENTITY" "$PKG_PATH"

echo ""
echo "✅ Mac App Store package ready:"
echo "   $PKG_PATH"
echo "   version=${APP_VERSION} build=${BUILD_NUMBER}"
echo ""
echo "Next: upload to App Store Connect using Transporter."
