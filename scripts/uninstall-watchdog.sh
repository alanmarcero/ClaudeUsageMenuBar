#!/bin/bash
# Removes the relaunch watchdog LaunchAgent installed by scripts/install-watchdog.sh.
set -euo pipefail

LABEL="com.alanmarcero.claudeusagemenubar.watchdog"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST"

echo "Watchdog removed."
