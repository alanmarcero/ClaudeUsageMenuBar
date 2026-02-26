# Claude Usage Menu Bar

A macOS menu bar app that displays your Claude.ai usage.

## Features

- Shows usage percentage in menu bar
- Daily and weekly limits with reset countdowns
- Email, organization, and plan display
- Color-coded thresholds (green < 55%, yellow 55-84%, red 85%+)
- Auto-refresh every 30 seconds

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
