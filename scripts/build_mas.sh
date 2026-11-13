#!/bin/zsh
set -euo pipefail

APP_NAME="MenuBarCalendar"
CONFIGURATION="release"
PKG_PATH="dist/${APP_NAME}.pkg"

source "${0:A:h}/bundle-common.sh"

resolve_version "${1:-}"

# --- Certificates for Mac App Store ---------------------------------------------
# Override by env, e.g. SIGN_APP_IDENTITY="Apple Distribution: xianyong zhu (7KURWGBJYX)"
SIGN_APP_IDENTITY="${SIGN_APP_IDENTITY:-Apple Distribution}"
SIGN_INSTALLER_IDENTITY="${SIGN_INSTALLER_IDENTITY:-3rd Party Mac Developer Installer}"

echo "==> Universal build (arm64 + x86_64)"
build_universal_binary

echo "==> Assemble .app bundle"
assemble_bundle
compile_icon_assets
write_plist_and_resources

# Embed provisioning profile (required for Mac App Store / TestFlight)
SIGN_ENTITLEMENTS_FILE="$ENTITLEMENTS_FILE"
if [[ -f "Resources/embedded.provisionprofile" ]]; then
  # Strip quarantine xattr so MAS uploads don't fail with ITMS-91109
  xattr -cr "Resources/embedded.provisionprofile" 2>/dev/null || true
  cp "Resources/embedded.provisionprofile" "${APP_DIR}/Contents/embedded.provisionprofile"
  echo "==> Embedded provisioning profile"

  # Merge provisioning profile entitlements with app entitlements so the
  # code signature includes application-identifier (required by ITMS-90886)
  TMP_PROF_ENT="$(mktemp -t profent).plist"
  TMP_PROF_MERGED="$(mktemp -t profmerged).plist"
  security cms -D -i "Resources/embedded.provisionprofile" \
    > "${TMP_PROF_ENT}.raw.plist" 2>/dev/null
  plutil -extract Entitlements xml1 \
    -o "${TMP_PROF_ENT}" "${TMP_PROF_ENT}.raw.plist"
  cp "${TMP_PROF_ENT}" "${TMP_PROF_MERGED}"
  /usr/libexec/PlistBuddy -c "Merge ${ENTITLEMENTS_FILE}" "${TMP_PROF_MERGED}"
  SIGN_ENTITLEMENTS_FILE="${TMP_PROF_MERGED}"
  rm -f "${TMP_PROF_ENT}.raw.plist" "${TMP_PROF_ENT}"
else
  echo "Warning: Resources/embedded.provisionprofile not found."
  echo "         Mac App Store / TestFlight uploads will fail without it."
  echo "         Download from developer.apple.com and place it here."
fi

echo "==> Strip quarantine xattr from .app"
xattr -cr "$APP_DIR" 2>/dev/null || true

echo "==> Codesign .app with ${SIGN_APP_IDENTITY}"
codesign --force --sign "$SIGN_APP_IDENTITY" --options runtime --timestamp \
  --entitlements "$SIGN_ENTITLEMENTS_FILE" "$APP_DIR"

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
