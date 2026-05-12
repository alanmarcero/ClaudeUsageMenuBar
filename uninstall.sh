#!/bin/bash

APP_NAME="ClaudeUsageMenuBar"

echo "Uninstalling $APP_NAME..."

pkill -f "$APP_NAME" 2>/dev/null || true
rm -rf "/Applications/$APP_NAME.app"

echo "Done!"
