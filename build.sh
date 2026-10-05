#!/bin/bash
# Builds "Clipboard History.app" (runs on Apple Silicon and Intel Macs)
# and a "Clipboard History.dmg" installer into ./build
#
#   ./build.sh            build the app and the .dmg
#   ./build.sh install    also install it into /Applications and open it
set -euo pipefail
cd "$(dirname "$0")"

NAME="Clipboard History"
APP="build/$NAME.app"
DMG="build/$NAME.dmg"
MIN_OS="14.0"

echo "→ Compiling for Apple Silicon and Intel…"
swift build -c release --triple "arm64-apple-macosx$MIN_OS"
swift build -c release --triple "x86_64-apple-macosx$MIN_OS"

echo "→ Assembling $NAME.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create \
  ".build/arm64-apple-macosx/release/ClipHistory" \
  ".build/x86_64-apple-macosx/release/ClipHistory" \
  -output "$APP/Contents/MacOS/ClipHistory"

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
swiftc -O -o build/make_icon Sources/ClipHistory/IconRenderer.swift scripts/make_icon/main.swift
build/make_icon "$ICONSET"
rm -f build/make_icon
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundleDisplayName</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>local.cliphistory</string>
    <key>CFBundleExecutable</key><string>ClipHistory</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"

echo "→ Making $NAME.dmg…"
STAGE="build/dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "scripts/How to Install.txt" "$STAGE/"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "✓ Built: $APP"
echo "✓ Built: $DMG  (send this file to friends)"

if [[ "${1:-}" == "install" ]]; then
  echo "→ Installing into /Applications…"
  pkill -x ClipHistory 2>/dev/null || true
  sleep 1
  rm -rf "/Applications/$NAME.app"
  cp -R "$APP" "/Applications/"
  open "/Applications/$NAME.app" --args --show
  echo "✓ Installed and opened /Applications/$NAME.app"
fi
