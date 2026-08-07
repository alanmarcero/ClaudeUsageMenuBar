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

Two things reduce it. The app now keeps its own cache small, so it's a less attractive target — it purges WebKit's response cache hourly while leaving your login alone. And an optional watchdog brings it back within a minute if macOS does kill it:

```bash
bash scripts/install-watchdog.sh     # from a clone of this repo
```

That installs a LaunchAgent which checks every 60 seconds and reopens the app if it isn't running. Quitting on purpose stays quit — the app leaves a marker behind when you use **Quit**, and the watchdog respects it until you next open the app yourself. `./install.sh` sets the watchdog up for you; skip it with `NO_WATCHDOG=1 ./install.sh`. Remove it any time:

```bash
bash scripts/uninstall-watchdog.sh
```

## Uninstall

Quit the app and drag **ClaudeUsageMenuBar.app** from Applications to the Trash. If you installed the watchdog, run `bash scripts/uninstall-watchdog.sh` first.

## Building from source

If you'd rather build it yourself, you need macOS 13+ and Xcode 14+:

```bash
./install.sh
```

This builds a release version, installs it to `/Applications`, and sets up the relaunch watchdog described above. Or open `ClaudeUsageMenuBar.xcodeproj` in Xcode and run it with Cmd+R.

## License

MIT
