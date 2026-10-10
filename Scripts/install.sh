#!/bin/bash
# Builds MatrixRain.saver (Release, universal) and installs it for the current user.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild build -project MatrixRain.xcodeproj -scheme MatrixRain -configuration Release \
    -derivedDataPath build/DerivedData -quiet

SAVER="build/DerivedData/Build/Products/Release/MatrixRain.saver"
DEST="$HOME/Library/Screen Savers"
mkdir -p "$DEST"
rm -rf "$DEST/MatrixRain.saver"
cp -R "$SAVER" "$DEST/"

# legacyScreenSaver caches loaded bundles; restart it so the new build is picked up.
killall legacyScreenSaver 2>/dev/null || true

echo "Installed $DEST/MatrixRain.saver ($(lipo -archs "$DEST/MatrixRain.saver/Contents/MacOS/MatrixRain"))"
