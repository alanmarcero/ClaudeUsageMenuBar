# Claude Usage Menu Bar

A macOS menu bar app that shows your **Claude** (claude.ai) and **OpenAI Codex** (chatgpt.com) usage limits.

## What it shows

- Your current usage percentage in the menu bar. Hover over the icon for a summary of each provider.
- A dropdown with each provider's daily and weekly limits, reset countdowns, plan, and when it last refreshed
- Green, orange and red colors that show how close you are to a limit, with a warning icon above the red threshold
- Provider buttons at the top of the dropdown that choose which percentage appears in the menu bar

It saves your last reading, so your usage shows on launch instead of a dash. The last-updated time turns orange when the data is stale.

## Install

1. Download `ClaudeUsageMenuBar-<version>.zip` from the [latest release](https://github.com/alanmarcero/ClaudeUsageMenuBar/releases/latest).
2. Unzip it and drag **ClaudeUsageMenuBar.app** into your **Applications** folder.
3. Open it. A CPU icon appears in your menu bar.

The first time you open it, macOS may warn that it's from an unidentified developer. If so, open **System Settings > Privacy & Security**, scroll down, and click **Open Anyway**.

## Logging in

If Claude Code is signed in on your Mac, the app reads Claude usage with that login, and you do not need to sign in to Claude in the app.

Otherwise, click the menu bar icon, then click the person icon next to Claude or Codex. Sign in to each site once. The two logins are separate, so signing out of one does not sign out the other.

Click a provider button at the top of the dropdown to show that provider's percentage in the menu bar.

## Settings

Click **Settings…** in the dropdown to change the percentages at which the bars and numbers turn orange and red. The defaults are orange at 55% and red at 85%.

## Updating

The app updates itself through Sparkle. Click **Check for Updates...** in the dropdown, and if a newer version is available, it downloads and installs it. The app checks only when you ask.

## If the icon disappears on its own

When your disk gets close to full, macOS reclaims space by asking `cache_delete` to purge app caches, and it kills an app before it purges that app's cache. It does this only to apps it considers non-interactive. A menu bar app is one, so macOS stops this app and leaves windowed apps running. There's no crash report, because it isn't crashing. In the system log it looks like this:

```
runningboardd: Received termination request from [osservice<com.apple.cache_delete>]
  code:0xBADDD15C explanation:CacheDeleteAppContainerCaches requesting termination assertion
```

The app keeps its cache small so macOS is less likely to pick it. It purges WebKit's response cache at launch and every hour after that, and keeps your login. On one machine that cut the container from 880 MB to under 50 MB. If macOS stops it anyway, open it again from Applications. It purges the cache at launch and shows your last reading.

> Versions 1.4.0 and 1.4.1 shipped an optional relaunch watchdog, since dropped. If you installed it, remove it with:
> ```bash
> launchctl bootout "gui/$(id -u)/com.alanmarcero.claudeusagemenubar.watchdog"
> rm -f ~/Library/LaunchAgents/com.alanmarcero.claudeusagemenubar.watchdog.plist
> ```

## Uninstall

Quit the app and drag **ClaudeUsageMenuBar.app** from Applications to the Trash.

## Building from source

To build it yourself, you need macOS 13+ and Xcode 14+:

```bash
./install.sh
```

This builds a release version and installs it to `/Applications`. Or open `ClaudeUsageMenuBar.xcodeproj` in Xcode and run it with Cmd+R.

## License

MIT
