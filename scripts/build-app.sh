#!/bin/bash
# Builds a universal EdgeWake.app into .build/ and signs it.
#
# Signing identity, in order of preference:
#   1. $EDGEWAKE_SIGNING_IDENTITY (a name or SHA-1 from `security find-identity -v -p codesigning`)
#   2. the first "Apple Development" identity in the keychain
#   3. ad-hoc ("-"), which works but makes macOS ask for permissions again after every rebuild
# Keep the bundle ID and identity stable between builds so granted permissions stick.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/.build/EdgeWake.app"

swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/EdgeWake" "$APP/Contents/MacOS/EdgeWake"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

# SwiftPM resource bundles (KeyboardShortcuts, EdgeWake) are found through Bundle.main's resources.
# EdgeWake's own compiled strings are also copied out as .lproj folders, so plain Text("…") and
# String(localized:) resolve them from the main bundle.
for bundle in "$BIN_DIR"/*.bundle; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done
for lproj in "$BIN_DIR"/EdgeWake_EdgeWake.bundle/*.lproj "$BIN_DIR"/EdgeWake_EdgeWake.bundle/Contents/Resources/*.lproj; do
  [ -d "$lproj" ] && cp -R "$lproj" "$APP/Contents/Resources/"
done

# Localized Info.plist strings (the Local Network prompt).
cp -R "$ROOT"/Resources/*.lproj "$APP/Contents/Resources/"

IDENTITY="${EDGEWAKE_SIGNING_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')"
fi
if [ -z "$IDENTITY" ]; then
  echo "warning: no signing identity found; signing ad-hoc." >&2
  IDENTITY="-"
fi
codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP (signed with: $IDENTITY)"
