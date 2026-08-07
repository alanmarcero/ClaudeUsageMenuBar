#!/bin/bash
# Installs a LaunchAgent that brings the app back after macOS terminates it.
#
# Under disk pressure macOS asks cache_delete to reclaim space, and cache_delete kills an
# app before purging its container caches. It only does that to apps it rates
# NonInteractive, which is exactly what an LSUIElement menu bar app is — so this app gets
# terminated (code 0xBADDD15C) while windowed apps are spared, and a menu bar app that is
# gone looks identical to one sitting idle.
#
# Nothing inside the process can recover from that, hence an external agent. Two details
# make the obvious approaches fail:
#
#   * launchd's own KeepAlive does not work. The termination carries an
#     RBSPreventLaunchLimitation that blocks relaunch of the bundle id for the length of the
#     purge, so a single relaunch attempt loses the race. StartInterval retries instead,
#     and whichever attempt lands after the purge wins.
#   * The agent must not exec the binary directly. The app is sandboxed and needs to start
#     through LaunchServices, so this uses `open`.
#
# The agent stands down while the user-quit marker exists, so a deliberate Quit stays quit.
set -euo pipefail

APP_NAME="ClaudeUsageMenuBar"
BUNDLE_ID="com.alanmarcero.claudeusagemenubar"
LABEL="$BUNDLE_ID.watchdog"
APP_PATH="/Applications/$APP_NAME.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
MARKER="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support/user-quit"
CHECK_INTERVAL=60

CHECK="[ -f \"$MARKER\" ] &amp;&amp; exit 0; /usr/bin/pgrep -x \"$APP_NAME\" &gt;/dev/null &amp;&amp; exit 0; [ -d \"$APP_PATH\" ] || exit 0; exec /usr/bin/open -gj \"$APP_PATH\""

mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" <<PLIST_XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>$CHECK</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>$CHECK_INTERVAL</integer>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
PLIST_XML

plutil -lint "$PLIST" >/dev/null

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "Watchdog installed: checks every ${CHECK_INTERVAL}s, relaunches $APP_NAME if macOS killed it."
echo "  Remove it with: bash scripts/uninstall-watchdog.sh"
