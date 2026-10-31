#!/bin/bash
# Installs the latest Sleight release into /Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/ArfiArfath21/sleight/main/install.sh | bash
#
# Set INSTALL_DIR to install somewhere else.
set -euo pipefail

URL="https://github.com/ArfiArfath21/sleight/releases/latest/download/Sleight.dmg"
DEST="${INSTALL_DIR:-/Applications}"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Sleight runs on macOS only." >&2
  exit 1
fi

# Fall back to ~/Applications when /Applications isn't writable (non-admin users).
if [ ! -w "$DEST" ]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi

WORK=$(mktemp -d)
MOUNT="$WORK/mount"
cleanup() {
  hdiutil detach -quiet "$MOUNT" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "Downloading Sleight…"
curl -fsSL "$URL" -o "$WORK/Sleight.dmg"

mkdir -p "$MOUNT"
hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$MOUNT" "$WORK/Sleight.dmg"

# Quit a running copy so it can be replaced.
osascript -e 'tell application id "com.arfiarfath21.sleight" to quit' >/dev/null 2>&1 || true

echo "Installing to $DEST…"
rm -rf "$DEST/Sleight.app"
ditto "$MOUNT/Sleight.app" "$DEST/Sleight.app"
# curl doesn't mark downloads as quarantined, but clear it in case anything did.
find "$DEST/Sleight.app" -exec xattr -d com.apple.quarantine {} + 2>/dev/null || true

echo "Installed Sleight to $DEST/Sleight.app"
if [ -z "${INSTALL_DIR:-}" ]; then
  open "$DEST/Sleight.app"
fi
