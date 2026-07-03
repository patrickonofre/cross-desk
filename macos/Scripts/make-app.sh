#!/bin/bash
# Builds CrossDesk.app (menubar app) from the SPM executable.
# Output: macos/build/CrossDesk.app
#
# Signing: ad-hoc (`codesign -s -`) while there is no Apple Developer
# identity. macOS may re-ask for the TCC permissions after a rebuild because
# the ad-hoc signature changes — re-grant in System Settings when that happens.
# UNIVERSAL=1 builds a fat binary (arm64 + x86_64) for distribution.
set -euo pipefail

cd "$(dirname "$0")/../CrossDeskKit"

if [ "${UNIVERSAL:-0}" = "1" ]; then
    swift build -c release --arch arm64 --arch x86_64 --product CrossDeskApp
    BINARY=".build/apple/Products/Release/CrossDeskApp"
else
    swift build -c release --product CrossDeskApp
    BINARY=".build/release/CrossDeskApp"
fi

APP_DIR="../build/CrossDesk.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

cp "$BINARY" "$APP_DIR/Contents/MacOS/CrossDesk"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>dev.crossdesk.mac</string>
    <key>CFBundleName</key>
    <string>CrossDesk</string>
    <key>CFBundleExecutable</key>
    <string>CrossDesk</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_DIR"

echo "OK: $(cd "$(dirname "$APP_DIR")" && pwd)/$(basename "$APP_DIR")"
