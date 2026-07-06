#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="WeatherBar"
APP_BUNDLE="$ROOT/${APP_NAME}.app"

cd "$ROOT"

echo "Building ${APP_NAME} (universal: arm64 + x86_64)..."
swift build -c release --arch arm64 --arch x86_64

BINARY_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/${APP_NAME}"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
cp "$ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "Architectures: $(lipo -archs "$APP_BUNDLE/Contents/MacOS/${APP_NAME}")"
lipo "$APP_BUNDLE/Contents/MacOS/${APP_NAME}" -verify_arch x86_64 arm64

echo "Signing ${APP_NAME}.app..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "Build complete: $APP_BUNDLE"
echo "Run with: open \"$APP_BUNDLE\""
