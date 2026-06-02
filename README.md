# Claude Usage Menu Bar

A macOS menu bar app that shows your AI usage at a glance. It tracks both **Claude** (claude.ai) and **OpenAI Codex** (chatgpt.com).

## What it shows

- Your current usage percentage right in the menu bar
- A dropdown with each provider's daily and weekly limits, plus reset countdowns
- Color coding so you can see at a glance how close you are: green under 55%, yellow 55-84%, red 85% and up
- A picker to choose which provider's percentage appears in the menu bar

## Install

1. Download `ClaudeUsageMenuBar-<version>.zip` from the [latest release](https://github.com/alanmarcero/ClaudeUsageMenuBar/releases/latest).
2. Unzip it and drag **ClaudeUsageMenuBar.app** into your **Applications** folder.
3. Open it. A CPU icon appears in your menu bar.

The first time you open it, macOS may warn that it's from an unidentified developer. If so, open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**.

## Logging in

Click the menu bar icon and choose **Open Claude / Login** (and **Open Codex / Login** if you use Codex). Sign in to each site once, and your usage shows up automatically. The two logins are independent, so signing out of one leaves the other alone.

Use the **Menu bar** picker in the dropdown to choose which provider's percentage is shown in the menu bar.

## Updating

The app updates itself through Sparkle. Click **Check for Updates...** in the dropdown, and if a newer version is available it will download and install it. There's no background nagging; it only checks when you ask.

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
