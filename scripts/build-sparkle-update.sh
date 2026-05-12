#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ClaudeUsageMenuBar"
PROJECT="$ROOT_DIR/$APP_NAME.xcodeproj"
BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
REPO_SLUG="${REPO_SLUG:-alanmarcero/ClaudeUsageMenuBar}"

TAG="${1:-}"

echo "Building release app..."
xcodebuild -project "$PROJECT" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -quiet \
    build

APP_BUNDLE="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Build failed: $APP_BUNDLE was not created."
    exit 1
fi

SHORT_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")"
BUILD_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")"

if [ -z "$TAG" ]; then
    TAG="v$SHORT_VERSION"
fi

mkdir -p "$DIST_DIR"

ZIP_NAME="$APP_NAME-$SHORT_VERSION.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
APPCAST_PATH="$DIST_DIR/appcast.xml"

rm -f "$ZIP_PATH" "$APPCAST_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

SIGN_UPDATE="$(find "$ROOT_DIR/build" "$HOME/Library/Developer/Xcode/DerivedData" \
    -path "*/Sparkle/bin/sign_update" \
    -type f 2>/dev/null | head -n 1)"

if [ -z "$SIGN_UPDATE" ]; then
    echo "Could not find Sparkle's sign_update tool. Run scripts/generate-sparkle-key.sh first."
    exit 1
fi

SIGNATURE="$("$SIGN_UPDATE" "$ZIP_PATH")"
DOWNLOAD_URL="https://github.com/$REPO_SLUG/releases/download/$TAG/$ZIP_NAME"
PUB_DATE="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S %z")"

cat > "$APPCAST_PATH" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Claude Usage Menu Bar Updates</title>
    <link>https://github.com/$REPO_SLUG</link>
    <description>Most recent Claude Usage Menu Bar release.</description>
    <language>en</language>
    <item>
      <title>Version $SHORT_VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD_VERSION</sparkle:version>
      <sparkle:shortVersionString>$SHORT_VERSION</sparkle:shortVersionString>
      <enclosure url="$DOWNLOAD_URL" $SIGNATURE type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML

echo "Created:"
echo "  $ZIP_PATH"
echo "  $APPCAST_PATH"
echo
echo "Upload both files to GitHub release $TAG."
