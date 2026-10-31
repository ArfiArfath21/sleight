#!/usr/bin/env bash
# Builds Sleight.app, signs it with a stable identity and installs it to
# ~/Applications. A stable signature + path keeps Camera/Accessibility grants
# valid across rebuilds.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
APP_DIR="$HOME/Applications/Sleight.app"
IDENTITY="${SLEIGHT_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"

swift build -c "$CONFIG" --product Sleight
swift build -c "$CONFIG" --product sleight-icon
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/Sleight"

# Render the icon from code (Sources/SleightBrand) so it never drifts from the logo.
ICON_DIR=".build/icon"
rm -rf "$ICON_DIR"
"$BIN_DIR/sleight-icon" "$ICON_DIR" >/dev/null
iconutil -c icns "$ICON_DIR/Sleight.iconset" -o "$ICON_DIR/AppIcon.icns"

# Quit a running copy so the binary can be replaced.
pkill -x Sleight 2>/dev/null || true

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp "$BIN" "$APP_DIR/Contents/MacOS/Sleight"
cp "$ICON_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" --entitlements Resources/Sleight.entitlements "$APP_DIR"
else
    echo "warning: no signing identity found, using ad-hoc (permissions reset on every build)" >&2
    codesign --force --sign - --entitlements Resources/Sleight.entitlements "$APP_DIR"
fi

echo "Installed $APP_DIR"
