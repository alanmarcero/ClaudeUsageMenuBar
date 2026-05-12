#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/ClaudeUsageMenuBar.xcodeproj"
INFO_PLIST="$ROOT_DIR/ClaudeUsageMenuBar/Info.plist"

echo "Resolving Sparkle package..."
xcodebuild -resolvePackageDependencies \
    -project "$PROJECT" \
    -scheme ClaudeUsageMenuBar \
    -quiet

GENERATE_KEYS="$(find "$ROOT_DIR/build" "$HOME/Library/Developer/Xcode/DerivedData" \
    -path "*/Sparkle/bin/generate_keys" \
    -type f 2>/dev/null | head -n 1)"

if [ -z "$GENERATE_KEYS" ]; then
    echo "Could not find Sparkle's generate_keys tool. Open the project in Xcode once, or resolve packages again."
    exit 1
fi

OUTPUT="$("$GENERATE_KEYS")"
PUBLIC_KEY="$(printf "%s\n" "$OUTPUT" | awk '
    /<string>/ {
        gsub(/.*<string>/, "")
        gsub(/<\/string>.*/, "")
        print
        exit
    }
    /^[[:space:]]*[A-Za-z0-9+\/]+={0,2}[[:space:]]*$/ {
        gsub(/[[:space:]]/, "")
        print
        exit
    }
')"

if [ -z "$PUBLIC_KEY" ]; then
    echo "$OUTPUT"
    echo "Could not parse the public key from Sparkle generate_keys output."
    exit 1
fi

/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC_KEY" "$INFO_PLIST"

echo "Saved SUPublicEDKey to $INFO_PLIST"
echo "Keep the private key in your Keychain backed up. Sparkle uses it to sign future updates."
