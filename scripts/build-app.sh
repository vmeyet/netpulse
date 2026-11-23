#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NetPulse"
BUNDLE_ID="com.vmeyet.netpulse"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "${1:?usage: build-app.sh <dest-dir>}"
DEST="$(cd "$1" && pwd)"
APP="$DEST/$APP_NAME.app"
VERSION="${VERSION:-$(git -C "$ROOT" describe --tags 2>/dev/null || echo 0.0.0-dev)}"
VERSION="${VERSION#v}"
BUILD=(swift build -c release --arch arm64 --arch x86_64)

cd "$ROOT"
"${BUILD[@]}"
BIN="$("${BUILD[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>$APP_NAME</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
	<key>CFBundleName</key><string>$APP_NAME</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$VERSION</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

if [[ -n "${DEVELOPER_ID:-}" ]]; then
	codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
else
	codesign --force --sign - "$APP"
fi
