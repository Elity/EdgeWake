#!/bin/bash
# Packages .build/EdgeWake.app into .build/EdgeWake-<version>.dmg with an Applications shortcut.
set -euo pipefail

cd "$(dirname "$0")/.."
"$PWD/scripts/build-app.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
STAGING="$(mktemp -d)"
DMG=".build/EdgeWake-$VERSION.dmg"
trap 'rm -rf "$STAGING"' EXIT

cp -R .build/EdgeWake.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "EdgeWake" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
echo "Built $DMG"
