#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClaudeUsageMenuBar"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
INSTALL_DIR="/Applications"

echo "Building $APP_NAME..."

xcodebuild -project "$SCRIPT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -quiet \
    build

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: Build failed"
    exit 1
fi

echo "Installing to $INSTALL_DIR..."
pkill -f "$APP_NAME" 2>/dev/null || true
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP_BUNDLE" "$INSTALL_DIR/"
rm -rf "$BUILD_DIR"

# Remove any legacy CDHash-locked WebKit WebCrypto keychain item; the app now provides
# its own persistent WebCrypto master key via WKWebsiteDataStore's delegate.
security delete-generic-password -a "com.apple.WebKit.WebCrypto.master+com.alanmarcero.claudeusagemenubar" 2>/dev/null || true

echo "Starting app..."
open "$INSTALL_DIR/$APP_NAME.app"

echo "Done! Look for the icon in your menu bar."
