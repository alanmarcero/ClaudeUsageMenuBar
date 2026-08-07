# Claude Usage Menu Bar

A macOS menu bar app that shows your AI usage at a glance. It tracks both **Claude** (claude.ai) and **OpenAI Codex** (chatgpt.com).

## What it shows

- Your current usage percentage right in the menu bar — hover the icon for a quick summary of every provider
- A dropdown with each provider's daily and weekly limits, reset countdowns, plan, and when it last refreshed
- Color coding so you can see at a glance how close you are (green / orange / red, with a warning icon once you cross the red threshold)
- A picker to choose which provider's percentage appears in the menu bar

It remembers your last reading, so your usage appears immediately on launch instead of a dash, and it flags when the data is stale.

## Install

1. Download `ClaudeUsageMenuBar-<version>.zip` from the [latest release](https://github.com/alanmarcero/ClaudeUsageMenuBar/releases/latest).
2. Unzip it and drag **ClaudeUsageMenuBar.app** into your **Applications** folder.
3. Open it. A CPU icon appears in your menu bar.

The first time you open it, macOS may warn that it's from an unidentified developer. If so, open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**.

## Logging in

Click the menu bar icon and choose **Open Claude / Login** (and **Open Codex / Login** if you use Codex). Sign in to each site once, and your usage shows up automatically. The two logins are independent, so signing out of one leaves the other alone.

Use the **Menu bar** picker in the dropdown to choose which provider's percentage is shown in the menu bar.

## Settings

Click **Settings…** in the dropdown to customize the color thresholds — the percentages at which the bars and numbers turn orange and red (defaults: orange at 55%, red at 85%).

## Updating

The app updates itself through Sparkle. Click **Check for Updates...** in the dropdown, and if a newer version is available it will download and install it. There's no background nagging; it only checks when you ask.

## If the icon disappears on its own

When your disk gets close to full, macOS reclaims space by asking `cache_delete` to purge app caches — and it kills an app before purging that app's cache. It only does this to apps it considers non-interactive, which is exactly what a menu bar app is, so this app gets terminated while windowed apps are left alone. There's no crash report, because it isn't crashing. In the system log it looks like this:

```
runningboardd: Received termination request from [osservice<com.apple.cache_delete>]
  code:0xBADDD15C explanation:CacheDeleteAppContainerCaches requesting termination assertion
```

The app keeps its own cache small so it's a less attractive target: it purges WebKit's response cache when it starts and hourly after that, leaving your login alone. On one machine that cut the container from 880 MB to under 50 MB. If it does get killed anyway, reopening it from Applications is the fix — it'll purge on launch and pick up where it left off.

> Versions 1.4.0 and 1.4.1 shipped an optional relaunch watchdog, since dropped. If you installed it, remove it with:
> ```bash
> launchctl bootout "gui/$(id -u)/com.alanmarcero.claudeusagemenubar.watchdog"
> rm -f ~/Library/LaunchAgents/com.alanmarcero.claudeusagemenubar.watchdog.plist
> ```

## Uninstall

Quit the app and drag **ClaudeUsageMenuBar.app** from Applications to the Trash.

## Building from source

If you'd rather build it yourself, you need macOS 13+ and Xcode 14+:

```bash
./install.sh
```

This builds a release version and installs it to `/Applications`. Or open `ClaudeUsageMenuBar.xcodeproj` in Xcode and run it with Cmd+R.

## License

MIT
