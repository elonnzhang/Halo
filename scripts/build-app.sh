#!/usr/bin/env bash
# Package Halo as a proper macOS .app bundle.
#
# Steps:
#   1. swift build -c release for arm64 + x86_64
#   2. lipo the two slices into a universal Mach-O
#   3. Assemble dist/Halo.app/Contents/{MacOS,Resources}
#   4. Copy executable + Info.plist + Halo.icns
#   5. Ad-hoc codesign (so Gatekeeper at least lets the user open it once)
#
# Output: dist/Halo.app (universal: arm64 + x86_64, macOS 12+)
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

echo "==> swift build (${CONFIG}) for arm64"
swift build -c "$CONFIG" --arch arm64
ARM_BIN=".build/arm64-apple-macosx/${CONFIG}/${APP_NAME}"
[[ -x "$ARM_BIN" ]] || { echo "error: arm64 build missing at $ARM_BIN" >&2; exit 1; }

echo "==> swift build (${CONFIG}) for x86_64"
swift build -c "$CONFIG" --arch x86_64
X86_BIN=".build/x86_64-apple-macosx/${CONFIG}/${APP_NAME}"
[[ -x "$X86_BIN" ]] || { echo "error: x86_64 build missing at $X86_BIN" >&2; exit 1; }

echo "==> assemble ${APP_PATH}"
rm -rf "$APP_PATH"
mkdir -p "$MACOS" "$RESOURCES"

echo "==> lipo arm64 + x86_64 → universal Mach-O"
lipo -create "$ARM_BIN" "$X86_BIN" -output "$MACOS/$APP_NAME"
lipo -info "$MACOS/$APP_NAME" | sed 's/^/    /'

cp Resources/Info.plist "$CONTENTS/Info.plist"

# Make sure the icon exists. If not, regenerate it.
if [[ ! -f Resources/Halo.icns ]]; then
    echo "==> rebuilding icon"
    swift scripts/render-icon.swift Resources/Halo.iconset
    iconutil -c icns Resources/Halo.iconset -o Resources/Halo.icns
fi
cp Resources/Halo.icns "$RESOURCES/Halo.icns"

# Copy *.lproj localization bundles. SwiftUI `Text("key")` looks up keys
# from `Bundle.main`, so dropping `<lang>.lproj/Localizable.strings` into
# the .app's main Resources is enough for system locale to pick them up.
for lproj in Resources/*.lproj; do
    [ -d "$lproj" ] || continue
    cp -R "$lproj" "$RESOURCES/"
done

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
