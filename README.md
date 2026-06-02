# Claude Usage Menu Bar

A macOS menu bar app that displays your AI usage. It tracks both **Claude** (claude.ai) and **OpenAI Codex** (chatgpt.com), and is provider-agnostic — adding another provider is a descriptor plus a scraping script.

## Features

- Tracks multiple providers: Claude and Codex, each in its own section
- Menu bar shows one provider's percentage; a "Menu bar" picker chooses which (scales to more providers)
- Per-provider daily and weekly limits with reset countdowns
- Per-provider login and logout
- Email and plan display when the provider exposes them
- Codex is shown as percent **used** to match Claude (its page reports percent remaining)
- Color-coded thresholds (green < 55%, yellow 55-84%, red 85%+)
- Auto-refresh every 30 seconds
- Manual in-app update checks powered by Sparkle

## Requirements

- macOS 13.0+
- Xcode 14.0+ (for building)

## Installation

```bash
./install.sh
```

Or manually:
1. Open `ClaudeUsageMenuBar.xcodeproj`
2. Build and run (Cmd+R)

## Updates

The app uses Sparkle for in-app updates. Click **Check for Updates...** in the menu bar popover to manually check GitHub Releases for a newer version. Automatic background checks are disabled, so update checks only happen when the user asks for them.

The app reads its appcast from:

```text
https://github.com/alanmarcero/ClaudeUsageMenuBar/releases/latest/download/appcast.xml
```

### First Sparkle Setup

Before publishing the first Sparkle update, generate the Sparkle signing key and embed the public key:

```bash
./scripts/generate-sparkle-key.sh
```

This stores the private signing key in your macOS Keychain and writes the matching public key into `ClaudeUsageMenuBar/Info.plist`. Back up the private key; future updates must be signed with the same key.

### Publishing an Update

For each release, increment `CFBundleVersion` and `CFBundleShortVersionString`, then build the update assets:

```bash
./scripts/build-sparkle-update.sh v1.1
```

Upload both files from `dist/` to the matching GitHub release:

- `ClaudeUsageMenuBar-<version>.zip`
- `appcast.xml`

The release tag passed to the script must match the GitHub release tag, because the generated appcast points at that tag's zip asset.

## First-Time Setup

1. Click the menu bar icon
2. For each provider you want to track, click "Open \<Provider\> / Login" (e.g. "Open Claude / Login", "Open Codex / Login")
3. Log in to that provider's site
4. Usage appears automatically; use the "Menu bar" picker to choose which provider's percentage shows in the menu bar

Sessions are independent per provider — logging out of one does not affect the other.

## Uninstall

```bash
./uninstall.sh
```

## License

MIT
