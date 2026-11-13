#!/bin/zsh
# Shared bundle assembly for build_app.sh and build_mas.sh.
# The sourcing script must set APP_NAME and CONFIGURATION first,
# then call the functions in order:
#   resolve_version [version-arg]
#   build_universal_binary
#   assemble_bundle
#   compile_icon_assets
#   write_plist_and_resources
# Signing differs per distribution channel and stays in the caller.

BUILD_DIR=".build"
APP_DIR="dist/${APP_NAME}.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"
ENTITLEMENTS_FILE="MenuBarCalendar.entitlements"

# --- Version -------------------------------------------------------------------
# Priority: $1 arg > APP_VERSION env > latest git tag > "1.0.0"
resolve_version() {
  APP_VERSION="${1:-${APP_VERSION:-}}"
  if [[ -z "$APP_VERSION" ]]; then
    APP_VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
  fi
  APP_VERSION="${APP_VERSION:-1.0.0}"
  BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
}

# --- Universal build (arm64 + x86_64) ---------------------------------------------
build_universal_binary() {
  swift build -c "$CONFIGURATION" --arch arm64 --arch x86_64

  # Universal products land in .build/apple/Products/<Config>/
  BINARY_PATH="${BUILD_DIR}/apple/Products/${CONFIGURATION}/${APP_NAME}"
  if [[ ! -f "$BINARY_PATH" ]]; then
    # Fallback for toolchains without universal support
    BINARY_PATH="${BUILD_DIR}/${CONFIGURATION}/${APP_NAME}"
  fi
}

# --- LC_BUILD_VERSION sdk field fix -------------------------------------------------
# SwiftPM writes the deployment target (12.0) into the binary's sdk field, so the
# system renders with legacy styling and MenuBarExtra misses the macOS 26+
# Liquid Glass look. Rewrite it to the real SDK version; must run before codesign.
fix_sdk_build_version() {
  local binary="$1"
  local sdk_version tmp_bin
  sdk_version="$(xcrun --show-sdk-version 2>/dev/null || true)"
  if [[ -n "$sdk_version" ]] && command -v vtool >/dev/null 2>&1; then
    tmp_bin="$(mktemp -t binary)"
    if vtool -set-build-version macos 12.0 "$sdk_version" -replace \
         -output "$tmp_bin" "$binary"; then
      mv "$tmp_bin" "$binary"
    else
      rm -f "$tmp_bin"
      echo "Warning: vtool patch failed — panel may render with legacy styling."
    fi
  fi
}

# --- Assemble .app skeleton: dirs, binary, strip, sdk fix ---------------------------
assemble_bundle() {
  rm -rf "$APP_DIR"
  mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
  cp "$BINARY_PATH" "${MACOS_DIR}/${APP_NAME}"

  # Strip symbols (release only; .build/ original stays intact)
  strip -x "${MACOS_DIR}/${APP_NAME}"
  fix_sdk_build_version "${MACOS_DIR}/${APP_NAME}"
}

# --- Icon (Icon Composer -> Assets.car + AppIcon.icns) ------------------------------
# Preferred source: icon.icon (Icon Composer document) compiled with actool,
# producing a layered Assets.car (macOS 26+ Liquid Glass) and a legacy
# AppIcon.icns fallback for older macOS versions.
compile_icon_assets() {
  if [[ -d "icon.icon" ]]; then
    local tmp_icon actool
    tmp_icon="$(mktemp -d)"
    cp -R "icon.icon" "${tmp_icon}/AppIcon.icon"
    mkdir -p "${tmp_icon}/out"
    actool="$(xcrun -f actool)"
    "$actool" "${tmp_icon}/AppIcon.icon" \
      --compile "${tmp_icon}/out" \
      --platform macosx \
      --target-device mac \
      --minimum-deployment-target 12.0 \
      --app-icon AppIcon \
      --enable-on-demand-resources NO \
      --output-partial-info-plist "${tmp_icon}/info.plist"
    cp "${tmp_icon}/out/Assets.car" "${RESOURCES_DIR}/Assets.car"

    # Legacy fallback icns: render 1024px from Icon Composer so the icns carries
    # all standard sizes (actool's built-in icns only has 16-256pt renditions).
    local ictool="/Applications/Icon Composer.app/Contents/Executables/ictool"
    if [[ -x "$ictool" ]] && \
       "$ictool" "${tmp_icon}/AppIcon.icon" \
         --export-image --output-file "${tmp_icon}/icon1024.png" \
         --platform macOS --rendition Default \
         --width 1024 --height 1024 --scale 1 >/dev/null 2>&1; then
      ./make_icon.sh "${tmp_icon}/icon1024.png"
      cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
    else
      cp "${tmp_icon}/out/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
    fi
    rm -rf "$tmp_icon"
  elif [[ -f "Resources/AppIcon.icns" ]]; then
    cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
  else
    echo "Warning: Resources/AppIcon.icns not found — app will have no icon."
    echo "         Add icon.icon (Icon Composer) or run ./make_icon.sh <1024x1024.png>."
  fi
}

# --- Info.plist + PkgInfo + localized resources --------------------------------------
write_plist_and_resources() {
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
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>
</dict>
</plist>
PLIST

  printf 'APPL????\n' > "${APP_DIR}/Contents/PkgInfo"

  ditto "Resources/en.lproj" "${RESOURCES_DIR}/en.lproj"
  ditto "Resources/zh-Hans.lproj" "${RESOURCES_DIR}/zh-Hans.lproj"
  ditto "Resources/zh-Hant.lproj" "${RESOURCES_DIR}/zh-Hant.lproj"
  ditto "Resources/ja.lproj" "${RESOURCES_DIR}/ja.lproj"
}
