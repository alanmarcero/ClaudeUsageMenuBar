#!/bin/bash

APP_NAME="ClaudeUsageMenuBar"

echo "Uninstalling $APP_NAME..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/scripts/uninstall-watchdog.sh" 2>/dev/null || true

pkill -f "$APP_NAME" 2>/dev/null || true
rm -rf "/Applications/$APP_NAME.app"

echo "Done!"
