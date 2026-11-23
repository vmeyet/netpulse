#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RENDER="$ROOT/.build/render-svg"
ICONSET="$ROOT/.build/AppIcon.iconset"

mkdir -p "$ROOT/.build"
swiftc -O "$ROOT/scripts/render-svg.swift" -o "$RENDER"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
	"$RENDER" "$ROOT/Resources/AppIcon.svg" "$ICONSET/icon_${size}x${size}.png" "$size"
	"$RENDER" "$ROOT/Resources/AppIcon.svg" "$ICONSET/icon_${size}x${size}@2x.png" "$((size * 2))"
done

iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
echo "Wrote $ROOT/Resources/AppIcon.icns"
