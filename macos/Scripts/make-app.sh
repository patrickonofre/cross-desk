#!/bin/bash
# Builds CrossDesk.app (menubar app) from the SPM executable.
# Output: macos/build/CrossDesk.app
#
# Signing: uses the self-signed "CrossDesk Dev" identity when present in the
# keychain (stable identity → TCC permissions survive rebuilds). Falls back
# to ad-hoc, which makes macOS re-ask permissions after every rebuild.
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
    <string>7</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

if security find-identity -v -p codesigning 2>/dev/null | grep -q "CrossDesk Dev"; then
    SIGN_ID="CrossDesk Dev"
else
    SIGN_ID="-"
    echo "AVISO: identidade 'CrossDesk Dev' ausente — assinando ad-hoc (TCC vai re-pedir a cada build)"
fi
codesign --force --sign "$SIGN_ID" "$APP_DIR"
echo "Assinado com: $SIGN_ID"

echo "OK: $(cd "$(dirname "$APP_DIR")" && pwd)/$(basename "$APP_DIR")"
