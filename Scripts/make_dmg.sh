#!/usr/bin/env bash
# Builds Layouts and packages it into a DMG with a drag-to-Applications layout.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
case "$CONFIG" in
    release|debug) ;;
    *) echo "usage: make_dmg.sh [release|debug]" >&2; exit 2 ;;
esac

swift build -c "$CONFIG"
BIN=".build/$CONFIG/Layouts"
APP="dist/Layouts.app"

if [[ ! -x "$BIN" ]]; then
    echo "missing binary at $BIN — did the build succeed?" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Layouts"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Layouts</string>
    <key>CFBundleDisplayName</key><string>Layouts</string>
    <key>CFBundleIdentifier</key><string>com.latif.layouts</string>
    <key>CFBundleExecutable</key><string>Layouts</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>2.0</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAccessibilityUsageDescription</key><string>Layouts reads and moves windows through the Accessibility API.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

STAGE="dist/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Layouts.app"
ln -s /Applications "$STAGE/Applications"

DMG_RW="dist/Layouts-rw.dmg"
DMG_FINAL="dist/Layouts-2.0.dmg"
rm -f "$DMG_RW" "$DMG_FINAL"
hdiutil create -ov -volname "Layouts 2.0" -fs HFS+ -srcfolder "$STAGE" "$DMG_RW"
hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL"
rm -f "$DMG_RW"
hdiutil verify "$DMG_FINAL"

echo "Built $DMG_FINAL"
