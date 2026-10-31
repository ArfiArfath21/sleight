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
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Maestro"

# Quit a running copy so the binary can be replaced.
pkill -x Maestro 2>/dev/null || true

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp "$BIN" "$APP_DIR/Contents/MacOS/Maestro"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/"

if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" --entitlements Resources/Maestro.entitlements "$APP_DIR"
else
    echo "warning: no signing identity found, using ad-hoc (permissions reset on every build)" >&2
    codesign --force --sign - --entitlements Resources/Maestro.entitlements "$APP_DIR"
fi

echo "Installed $APP_DIR"
