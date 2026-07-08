#!/bin/bash
# Builds CrossDesk.app (menubar app) from the SPM executable.
# Output: macos/build/CrossDesk.app
#
# Signing: uses the self-signed "CrossDesk Dev" identity when present in the
# keychain (stable identity → TCC permissions survive rebuilds). Falls back
# to ad-hoc, which makes macOS re-ask permissions after every rebuild.
# UNIVERSAL=1 builds a fat binary (arm64 + x86_64) for distribution.
#
# Sparkle (sparkle-auto-update): the SPM dependency resolves as an
# xcframework under .build/artifacts, not a linked framework the way Xcode
# would embed it — so this script copies Sparkle.framework into
# Contents/Frameworks itself and signs it (with its nested XPC services and
# helper app) before signing the outer bundle. codesign requires
# inside-out order: nested code first, container last.
set -euo pipefail

cd "$(dirname "$0")/../CrossDeskKit"

if [ "${UNIVERSAL:-0}" = "1" ]; then
    swift build -c release --arch arm64 --arch x86_64 --product CrossDeskApp
    BINARY=".build/apple/Products/Release/CrossDeskApp"
    SPARKLE_ARCH_DIR=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
else
    swift build -c release --product CrossDeskApp
    BINARY=".build/release/CrossDeskApp"
    SPARKLE_ARCH_DIR=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
fi

APP_DIR="../build/CrossDesk.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"

cp "$BINARY" "$APP_DIR/Contents/MacOS/CrossDesk"
cp "../Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp -R "$SPARKLE_ARCH_DIR/Sparkle.framework" "$APP_DIR/Contents/Frameworks/Sparkle.framework"

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
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2.1</string>
    <key>CFBundleVersion</key>
    <string>22</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>O CrossDesk usa a rede local para encontrar e conectar suas máquinas.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_crossdesk._udp</string>
    </array>
    <key>SUFeedURL</key>
    <string>https://patrickonofre.github.io/cross-desk/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>rhtm2zpLsvnkuXRBkkdZOvB/GqCKtcL585bo6jRnP68=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUEnableSystemProfiling</key>
    <false/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
</dict>
</plist>
PLIST

if security find-identity -v -p codesigning 2>/dev/null | grep -q "CrossDesk Dev"; then
    SIGN_ID="CrossDesk Dev"
else
    SIGN_ID="-"
    echo "AVISO: identidade 'CrossDesk Dev' ausente — assinando ad-hoc (TCC vai re-pedir a cada build)"
fi

# Nested code first (deepest first), outer bundle last — codesign requirement.
# Sparkle's Downloader.xpc/Installer.xpc, its Autoupdate/Updater.app helpers,
# then the framework itself, then CrossDesk.app.
sign() {
    codesign --force --sign "$SIGN_ID" "$1"
    echo "  assinado: ${1#"$APP_DIR"/}"
}

FRAMEWORK="$APP_DIR/Contents/Frameworks/Sparkle.framework"
while IFS= read -r -d '' xpc; do sign "$xpc"; done \
    < <(find "$FRAMEWORK" -type d -name "*.xpc" -print0)
while IFS= read -r -d '' nested_app; do sign "$nested_app"; done \
    < <(find "$FRAMEWORK" -type d -name "*.app" -print0)
while IFS= read -r -d '' bin; do
    if file -b "$bin" 2>/dev/null | grep -q "Mach-O"; then sign "$bin"; fi
done < <(find "$FRAMEWORK" -type f -perm -u+x -print0)
sign "$FRAMEWORK"

codesign --force --sign "$SIGN_ID" "$APP_DIR"
echo "Assinado com: $SIGN_ID"

echo "OK: $(cd "$(dirname "$APP_DIR")" && pwd)/$(basename "$APP_DIR")"
