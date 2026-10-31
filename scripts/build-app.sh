#!/usr/bin/env bash
# Builds Maestro.app, signs it with a stable identity and installs it to
# ~/Applications. A stable signature + path keeps Camera/Accessibility grants
# valid across rebuilds.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
APP_DIR="$HOME/Applications/Maestro.app"
IDENTITY="${MAESTRO_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"

swift build -c "$CONFIG" --product Maestro
swift build -c "$CONFIG" --product maestro-icon
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/Maestro"

# Render the icon from code (Sources/MaestroBrand) so it never drifts from the logo.
ICON_DIR=".build/icon"
rm -rf "$ICON_DIR"
"$BIN_DIR/maestro-icon" "$ICON_DIR" >/dev/null
iconutil -c icns "$ICON_DIR/Maestro.iconset" -o "$ICON_DIR/AppIcon.icns"

# Quit a running copy so the binary can be replaced.
pkill -x Maestro 2>/dev/null || true

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp "$BIN" "$APP_DIR/Contents/MacOS/Maestro"
cp "$ICON_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" --entitlements Resources/Maestro.entitlements "$APP_DIR"
else
    echo "warning: no signing identity found, using ad-hoc (permissions reset on every build)" >&2
    codesign --force --sign - --entitlements Resources/Maestro.entitlements "$APP_DIR"
fi

echo "Installed $APP_DIR"
