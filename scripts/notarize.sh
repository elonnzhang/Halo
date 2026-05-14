#!/usr/bin/env bash
# Notarize the universal release .app via Apple's notary service.
#
# Prerequisites (one-time, per developer machine):
#
#   xcrun notarytool store-credentials halo-notary \
#       --apple-id "you@example.com" \
#       --team-id  "ABCDE12345" \
#       --password "app-specific-password"
#
# Then export the matching signing identity before `make app`:
#
#   export HALO_SIGNING_IDENTITY="Developer ID Application: Your Name (ABCDE12345)"
#   make app
#   ./scripts/notarize.sh
#
# What this does:
#   1. Zips dist/Halo.app to dist/Halo-<version>.zip for submission
#      (notarytool wants a flat archive of a Developer-ID-signed app).
#   2. Submits the zip with `--wait` so the script blocks until Apple
#      reports `Accepted` (~2–10 minutes typically).
#   3. Staples the notarization ticket back onto the .app so Gatekeeper
#      accepts it offline.
#   4. Runs `spctl --assess` to confirm Gatekeeper is happy.
#   5. Re-zips the stapled .app to a fresh dist zip ready for release.
#
# Bail-out matrix:
#   - "Notarization rejected"  → run `xcrun notarytool log <id> --keychain-profile halo-notary`
#                               to see why; common: missing hardened runtime,
#                               unsigned helper, com.apple.security.cs.allow-jit
#                               required for some PDFKit / WebKit child procs.
#   - "Unauthorized"           → Apple ID password expired / app-specific
#                               password revoked; redo store-credentials.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_PATH="dist/Halo.app"
PROFILE="${HALO_NOTARY_PROFILE:-halo-notary}"

[[ -d "$APP_PATH" ]] || { echo "error: $APP_PATH not found — run \`make app\` first" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
SUBMIT_ZIP="dist/Halo-${VERSION}-submit.zip"
FINAL_ZIP="dist/Halo-v${VERSION}.zip"

# Sanity: verify Developer ID, not ad-hoc
SIGN_AUTH="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 | awk -F= '/Authority/ {print $2; exit}')"
if [[ "$SIGN_AUTH" == "-" ]] || [[ "$SIGN_AUTH" == *"adhoc"* ]] || [[ -z "$SIGN_AUTH" ]]; then
    echo "error: $APP_PATH is ad-hoc signed. Set HALO_SIGNING_IDENTITY and run \`make app\` again." >&2
    exit 2
fi
echo "==> signing authority: $SIGN_AUTH"

echo "==> zip for submission"
rm -f "$SUBMIT_ZIP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$SUBMIT_ZIP"

echo "==> notarytool submit (--wait, profile=$PROFILE)"
xcrun notarytool submit "$SUBMIT_ZIP" \
    --keychain-profile "$PROFILE" \
    --wait

echo "==> staple"
xcrun stapler staple "$APP_PATH"

echo "==> verify staple"
xcrun stapler validate "$APP_PATH" | sed 's/^/    /'

echo "==> spctl assess (must say 'accepted')"
spctl --assess --verbose=2 --type execute "$APP_PATH" 2>&1 | sed 's/^/    /'

echo "==> repackage stapled .app → $FINAL_ZIP"
rm -f "$FINAL_ZIP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$FINAL_ZIP"

# SHA-256 alongside the zip so release notes can quote it
shasum -a 256 "$FINAL_ZIP" | tee "${FINAL_ZIP}.sha256"

du -sh "$FINAL_ZIP" | awk '{print "==> done: " $0}'
echo "    upload: ${FINAL_ZIP}"
echo "    checksum: $(cat "${FINAL_ZIP}.sha256")"
