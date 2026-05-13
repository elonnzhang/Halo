#!/usr/bin/env bash
# Package Halo as a proper macOS .app bundle.
#
# Steps:
#   1. swift build -c release
#   2. Assemble dist/Halo.app/Contents/{MacOS,Resources}
#   3. Copy executable + Info.plist + Halo.icns
#   4. Ad-hoc codesign (so Gatekeeper at least lets the user open it once)
#
# Output: dist/Halo.app
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Halo"
BUNDLE_NAME="${APP_NAME}.app"
DIST_DIR="dist"
APP_PATH="${DIST_DIR}/${BUNDLE_NAME}"
CONTENTS="${APP_PATH}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

CONFIG="${BUILD_CONFIG:-release}"

echo "==> swift build (${CONFIG})"
swift build -c "$CONFIG"

BIN_PATH=".build/${CONFIG}/${APP_NAME}"
if [[ ! -x "$BIN_PATH" ]]; then
    # Apple silicon places binaries under arm64-apple-macosx
    BIN_PATH=".build/arm64-apple-macosx/${CONFIG}/${APP_NAME}"
fi
if [[ ! -x "$BIN_PATH" ]]; then
    echo "error: cannot find built executable" >&2
    exit 1
fi

echo "==> assemble ${APP_PATH}"
rm -rf "$APP_PATH"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN_PATH" "$MACOS/$APP_NAME"
cp Resources/Info.plist "$CONTENTS/Info.plist"

# Make sure the icon exists. If not, regenerate it.
if [[ ! -f Resources/Halo.icns ]]; then
    echo "==> rebuilding icon"
    swift scripts/render-icon.swift Resources/Halo.iconset
    iconutil -c icns Resources/Halo.iconset -o Resources/Halo.icns
fi
cp Resources/Halo.icns "$RESOURCES/Halo.icns"

# Stamp PkgInfo (some Finder paths still read it)
printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "$APP_PATH"

echo "==> verify"
codesign --verify --verbose=2 "$APP_PATH" 2>&1 | sed 's/^/    /'
plutil -lint "$CONTENTS/Info.plist" | sed 's/^/    /'

du -sh "$APP_PATH" | awk '{print "==> done: " $0}'
echo "    install: cp -R ${APP_PATH} /Applications/"
echo "    run:     open ${APP_PATH}"
