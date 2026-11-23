#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NetPulse"
DEST="${1:-/Applications}"
APP="$DEST/$APP_NAME.app"
ROOT="$(cd "$(dirname "$0")" && pwd)"

"$ROOT/scripts/build-app.sh" "$DEST"

pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
pkill -f "$ROOT/.build/.*/$APP_NAME" 2>/dev/null || true

open "$APP"
echo "Installed and launched $APP"
