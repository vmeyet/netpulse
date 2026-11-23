#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NetPulse"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGING="$ROOT/.build/dmg"

rm -rf "$STAGING"
"$ROOT/scripts/build-app.sh" "$STAGING"
ln -s /Applications "$STAGING/Applications"

VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$STAGING/$APP_NAME.app/Contents/Info.plist")"
DMG="$ROOT/dist/$APP_NAME-$VERSION.dmg"
mkdir -p "$ROOT/dist"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -format UDZO -ov "$DMG"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
	codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
	xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
	xcrun stapler staple "$DMG"
fi

echo "Built $DMG"
