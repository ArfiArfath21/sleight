#!/usr/bin/env bash
# Builds Sleight.app into build/ and packages build/Sleight.dmg, the
# drag-to-Applications installer used for GitHub releases and Homebrew.
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf build && mkdir -p build/dmg
APP_DIR="$PWD/build/dmg/Sleight.app" ./scripts/build-app.sh
ln -s /Applications build/dmg/Applications
hdiutil create -quiet -volname Sleight -srcfolder build/dmg -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov build/Sleight.dmg
echo "Packaged build/Sleight.dmg"
shasum -a 256 build/Sleight.dmg
