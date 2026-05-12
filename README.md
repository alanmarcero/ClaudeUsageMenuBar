# Claude Usage Menu Bar

A macOS menu bar app that displays your Claude.ai usage.

## Features

- Shows usage percentage in menu bar
- Daily and weekly limits with reset countdowns
- Email, organization, and plan display
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
./scripts/build-sparkle-update.sh v1.0
```

Upload both files from `dist/` to the matching GitHub release:

- `ClaudeUsageMenuBar-<version>.zip`
- `appcast.xml`

The release tag passed to the script must match the GitHub release tag, because the generated appcast points at that tag's zip asset.

## First-Time Setup

1. Click the menu bar icon
2. Click "Open Usage Page / Login"
3. Log in to Claude.ai
4. Usage will appear automatically

## Uninstall

```bash
./uninstall.sh
```

## License

MIT
