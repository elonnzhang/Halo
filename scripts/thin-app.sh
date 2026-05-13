#!/usr/bin/env bash
# Produce an architecture-thinned copy of dist/Halo.app for users who
# want a smaller download than the universal binary.
#
#   bash scripts/thin-app.sh arm64
#   bash scripts/thin-app.sh x86_64
#
# Output lives at dist/thin-<arch>/Halo.app so the .app is always named
# "Halo.app" (the zip in scripts/build-app.sh / release.yml repackages
# this so the user sees "Halo.app" after extraction regardless of slice).
set -euo pipefail

ARCH="${1:?usage: thin-app.sh <arm64|x86_64>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SRC="dist/Halo.app"
DST_DIR="dist/thin-${ARCH}"
DST="${DST_DIR}/Halo.app"

[[ -d "$SRC" ]] || { echo "error: $SRC missing — run 'make app' first" >&2; exit 1; }

case "$ARCH" in
    arm64|x86_64) ;;
    *) echo "error: unsupported arch '$ARCH' (use arm64 or x86_64)" >&2; exit 1 ;;
esac

echo "==> thinning ${SRC} → ${DST} (${ARCH} only)"
rm -rf "$DST_DIR"
mkdir -p "$DST_DIR"
cp -R "$SRC" "$DST"
lipo "$SRC/Contents/MacOS/Halo" -thin "$ARCH" -output "$DST/Contents/MacOS/Halo"

echo "==> re-codesign (ad-hoc)"
codesign --force --deep --sign - "$DST" >/dev/null

echo "==> verify"
lipo -info "$DST/Contents/MacOS/Halo" | sed 's/^/    /'
codesign --verify "$DST" 2>&1 | sed 's/^/    /'
du -sh "$DST" | awk '{print "==> done: " $0}'
