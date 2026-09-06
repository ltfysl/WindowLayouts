#!/usr/bin/env bash
# Builds Layouts and assembles a codesigned .app bundle in dist/.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Layouts"
BUNDLE_ID="com.latif.layouts"
CONFIG="${1:-release}"

case "$CONFIG" in
    release|debug) ;;
    *) echo "usage: make_app.sh [release|debug]" >&2; exit 2 ;;
esac

swift build -c "$CONFIG"
BIN=".build/$CONFIG/$APP_NAME"
APP="dist/$APP_NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAccessibilityUsageDescription</key><string>Layouts reads and moves windows through the Accessibility API.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
