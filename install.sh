#!/bin/bash
# Installs the latest Clipboard History into /Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/10shaikhnuman-hue/clipboard-history/main/install.sh | bash
set -euo pipefail

NAME="Clipboard History"
URL="https://github.com/10shaikhnuman-hue/clipboard-history/releases/latest/download/Clipboard-History.dmg"
TMP="$(mktemp -d)"
trap 'hdiutil detach "$TMP/mnt" -quiet 2>/dev/null || true; rm -rf "$TMP"' EXIT

echo "→ Downloading $NAME…"
curl -fL --progress-bar "$URL" -o "$TMP/app.dmg"

echo "→ Installing into /Applications…"
hdiutil attach "$TMP/app.dmg" -nobrowse -quiet -mountpoint "$TMP/mnt"
pkill -x ClipHistory 2>/dev/null || true
rm -rf "/Applications/$NAME.app"
cp -R "$TMP/mnt/$NAME.app" /Applications/
xattr -cr "/Applications/$NAME.app"

open "/Applications/$NAME.app" --args --show
echo "✓ Installed. Press ⌘⇧V anywhere to open your clipboard history."
