#!/bin/bash
# Builds CrossDesk.app (menubar app) from the SPM executable.
# Output: macos/build/CrossDesk.app
#
# Signing: ad-hoc (`codesign -s -`) while there is no Apple Developer
# identity. macOS may re-ask for the TCC permissions after a rebuild because
# the ad-hoc signature changes — re-grant in System Settings when that happens.
set -euo pipefail

cd "$(dirname "$0")/../CrossDeskKit"
swift build -c release --product CrossDeskApp

APP_DIR="../build/CrossDesk.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

cp .build/release/CrossDeskApp "$APP_DIR/Contents/MacOS/CrossDesk"

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
    <string>1</string>
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
