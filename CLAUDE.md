# CLAUDE.md - Project Notes

## Maintenance & Scraping Strategy

The Claude.ai usage page is highly dynamic and frequently changes its DOM structure (tag names, class names, etc.). To handle this, the app uses a **label-centric** approach rather than a selector-centric one.

### How it Works
1.  **Label Search:** The scraper looks for specific text strings ("Current session", "All models", "Sonnet only", "Claude Design") in *all* common text elements (`p`, `div`, `span`).
2.  **Container Recovery:** Once a label is found, it traverses upwards to find the closest "row" container (usually a `flex-row` div) that contains both the label and its corresponding percentage/reset data.
3.  **Flexible Extraction:** Inside that container, it uses regex to find `X% used` and looks for any element containing the word "Reset" or time patterns.
4.  **Global Fallback:** If the labels cannot be matched (e.g., they changed to "Current Usage"), the scraper falls back to a document-wide search for all `% used` patterns to ensure basic functionality.

### Troubleshooting (When it breaks)
1.  **Click "Show Debug Info"** in the menu bar.
2.  **Inspect the `logs` array:** It will tell you exactly which labels were found and which containers failed.
3.  **Check `bodyText`:** The debug info includes the first 1000 characters of the page text. Check if the labels ("Current session", etc.) have changed.
4.  **Update `UsageService.swift`:**
    *   If labels changed, update the strings in `findRowData` calls.
    *   If percentages aren't being found, check the `percentMatch` regex.
    *   If the page isn't loading, check the `findHeading` logic (it currently looks for "usage limits").

### Validation Protocol
After any change to the scraper:
```bash
./install.sh
# Then check the "Show Debug Info" in the app to ensure all fields populate.
```

---

## IMPORTANT: Always Run Validation After Code Changes

**After ANY code change in this repository, you MUST run the validation steps:**

```bash
# 1. Run tests
xcodebuild test -project ClaudeUsageMenuBar.xcodeproj -scheme ClaudeUsageMenuBar -destination 'platform=macOS'

# 2. Build the app
xcodebuild -project ClaudeUsageMenuBar.xcodeproj -scheme ClaudeUsageMenuBar -configuration Release build

# 3. Kill and redeploy the app
pkill -x ClaudeUsageMenuBar; sleep 1; ./install.sh
```

Do not consider a task complete until all steps pass successfully.

---

## Clean Code Principles

This project follows these clean code principles:

1. **Meaningful Names** - Names reveal intent without comments. Use searchable, pronounceable names.
2. **Small, Focused Functions** - Functions do one thing, have minimal parameters, operate at single abstraction level.
3. **No Side Effects** - Functions either perform actions or return data, not both. Avoid hidden state changes.
4. **DRY (Don't Repeat Yourself)** - Single authoritative representation for each piece of knowledge.
5. **Single Responsibility Principle** - Each class/module has one reason to change.
6. **Comments Are a Last Resort** - Code is self-documenting. Comments explain *why*, not *what*.
7. **Consistent Formatting** - Related code grouped together, consistent style, minimal cognitive load.
8. **Error Handling** - Use exceptions, don't return null, separate error handling from business logic.
9. **Tests Are First-Class Code** - Fast, independent, repeatable, self-validating. One concept per test.
10. **Boy Scout Rule** - Leave code cleaner than you found it.

## Overview

Claude Usage Menu Bar is a macOS menu bar application that displays real-time Claude.ai API usage statistics. It scrapes usage data from `https://claude.ai/settings/usage` and displays daily/weekly limits, reset countdowns, and account information directly in the menu bar.

**Target URL**: `https://claude.ai/settings/usage`

## Tech Stack

- **Language**: Swift
- **Platform**: macOS 13.0+
- **UI Framework**: SwiftUI
- **Build System**: Xcode 14.0+
- **App Type**: Menu bar accessory (LSUIElement = true, no dock icon)

## Project Structure

```
ClaudeUsageMenuBar/
├── ClaudeUsageMenuBar/
│   ├── Models/
│   │   ├── UsageData.swift          # Data model for usage info
│   │   └── AppConfig.swift          # Color threshold configuration (singleton)
│   ├── Views/
│   │   ├── MenuBarView.swift        # Main menu bar dropdown UI
│   │   └── UsageWebView.swift       # Web view window for login/viewing
│   ├── Services/
│   │   └── UsageService.swift       # Core service: scraping, timers, state, WeeklyCountdownCalculator
│   ├── WebView/
│   │   ├── ClaudeWebView.swift      # SwiftUI wrapper for WKWebView
│   │   └── WebViewCoordinator.swift # Navigation delegate with domain whitelist
│   ├── ClaudeUsageMenuBarApp.swift  # App entry point, AppDelegate, WindowManager
│   ├── Info.plist
│   └── ClaudeUsageMenuBar.entitlements
├── ClaudeUsageMenuBarTests/         # 102 unit tests
│   ├── AppConfigTests.swift
│   ├── AppConfigEdgeCaseTests.swift
│   ├── UsageDataTests.swift
│   ├── ScrapedUsageDataTests.swift
│   ├── WeeklyCountdownCalculatorTests.swift
│   ├── WeeklyCountdownCalculatorDeterministicTests.swift
│   └── WebViewCoordinatorTests.swift
└── install.sh / uninstall.sh        # Build and install scripts
```

## Key Components

### UsageService (Services/UsageService.swift)
The central service that handles all data fetching and state management:
- Auto-refreshes every 30 seconds via background WKWebView
- JavaScript injection extracts usage data from DOM and Next.js streaming data (`__next_f`)
- Extracts: daily/weekly usage, percentages, reset times, email, org, plan
- Published properties trigger UI updates reactively

### MenuBarView (Views/MenuBarView.swift)
The menu bar dropdown UI:
- Shows account info, daily/weekly usage with progress bars
- Color-coded: green (<55%), orange (55-84%), red (85%+)
- Refresh countdown, debug info, logout, and quit buttons

### WebViewCoordinator (WebView/WebViewCoordinator.swift)
Controls WKWebView navigation:
- Whitelists claude.ai, anthropic.com, and OAuth providers (Google, Microsoft, Apple, Okta, Auth0, Clerk)
- Opens external links in system browser
- Detects login pages and updates logout state

### AppConfig (Models/AppConfig.swift)
Singleton for color thresholds:
- `yellowThreshold`: 55% (default)
- `redThreshold`: 85% (default)
- Persists to UserDefaults

## Build Commands

```bash
# Install to /Applications
./install.sh

# Uninstall
./uninstall.sh

# Build only
xcodebuild -project ClaudeUsageMenuBar.xcodeproj \
    -scheme ClaudeUsageMenuBar \
    -configuration Release build
```

## Architecture Notes

- **Pattern**: MVVM + Service Layer
- **State**: `@StateObject` for services, `@Published` for reactive updates
- **Threading**: `@MainActor` for UI safety
- **No external dependencies** - pure Apple frameworks (SwiftUI, WebKit, Combine, AppKit)

## Configuration Constants

### UsageService.swift Constants
| Constant | Value | Purpose |
|----------|-------|---------|
| `refreshInterval` | 30s | Time between auto-refreshes |
| `timerInterval` | 1.0s | Countdown tick interval |
| `initialRefreshDelay` | 2.0s | Delay before first refresh on launch |
| `scrapeDelay` | 2.0s | Delay after page load before scraping |
| `backgroundWebViewSize` | 1024x768 | Hidden webview dimensions |

### WebViewCoordinator.swift Constants
| Constant | Value | Purpose |
|----------|-------|---------|
| `redirectDelay` | 0.5s | Delay before redirecting to usage page |

### AppConfig Thresholds (UserDefaults)
| Key | Default | Purpose |
|-----|---------|---------|
| `yellowThreshold` | 55 | Percentage where color turns orange |
| `redThreshold` | 85 | Percentage where color turns red |

## Info.plist Settings

| Key | Value | Purpose |
|-----|-------|---------|
| `LSUIElement` | `true` | Hides app from Dock (menu bar only) |
| `CFBundleName` | ClaudeUsageMenuBar | Internal app name |
| `CFBundleDisplayName` | Claude Usage | User-facing name |
| `CFBundleVersion` | 1 | Build number |
| `CFBundleShortVersionString` | 1.0 | Version string |

## Entitlements

| Entitlement | Value | Purpose |
|-------------|-------|---------|
| `com.apple.security.app-sandbox` | `true` | Enables App Sandbox |
| `com.apple.security.network.client` | `true` | Allows outbound network connections |

## JavaScript Scraping Strategy

The scraper in `UsageService.swift` uses two extraction methods:
1. **DOM Parsing**: Searches for "X / Y" patterns and "X% used" text
2. **Next.js Data**: Parses `__next_f` script tags for user email, org, and plan info

Key regex patterns:
- Usage: `/(\d+(?:\.\d+)?)\s*\/\s*(\d+(?:\.\d+)?)/`
- Percentage: `/(\d+(?:\.\d+)?)\s*%\s*used/`
- Reset time: `/Reset(?:s)?\s+(Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+(\d{1,2}:\d{2}\s*(?:AM|PM)?)/i`

## Testing

Tests are in `ClaudeUsageMenuBarTests/` with **102 unit tests** covering core logic:

| Test File | Tests | Coverage |
|-----------|-------|----------|
| `AppConfigTests.swift` | 8 | Color threshold logic |
| `AppConfigEdgeCaseTests.swift` | 16 | Boundary conditions, full range coverage |
| `UsageDataTests.swift` | 11 | Display formatting, default values |
| `ScrapedUsageDataTests.swift` | 16 | UsageData model, state tests |
| `WeeklyCountdownCalculatorTests.swift` | 9 | Basic time parsing, day calculation |
| `WeeklyCountdownCalculatorDeterministicTests.swift` | 24 | Fixed-date tests for deterministic results |
| `WebViewCoordinatorTests.swift` | 17 | URL filtering, OAuth whitelisting, auth detection |

### Testability Patterns Used

**Default Parameter Injection** - Time-dependent functions accept optional date parameter:
```swift
// Allows deterministic testing with fixed dates
static func calculate(from resetString: String?, currentDate: Date = Date()) -> String?
```

**Internal Access for Testing** - Helper methods are `internal` (not `private`) for `@testable import`:
```swift
// WebViewCoordinator - testable helper methods
func isAllowedHost(_ host: String) -> Bool
func isAuthPage(_ urlString: String) -> Bool
func isClaudeMainPage(host: String, urlString: String) -> Bool
```

**Test Fixture Helpers** - Reusable date creation for deterministic tests:
```swift
private func createTestDate(hour: Int, minute: Int) -> Date {
    var components = DateComponents()
    components.year = 2025
    components.month = 1
    components.day = 2
    components.hour = hour
    components.minute = minute
    return Calendar.current.date(from: components)!
}
```

Run tests: Cmd+U in Xcode or `xcodebuild test -project ClaudeUsageMenuBar.xcodeproj -scheme ClaudeUsageMenuBar -destination 'platform=macOS'`

## Security

- App Sandbox enabled with network client permission only
- Session cookies stored in WKWebsiteDataStore
- Logout clears all claude.ai/anthropic.com session data
- No local storage of sensitive data

## Common Development Tasks

### Modify color thresholds
Edit `AppConfig.swift` - change `yellowThreshold` and `redThreshold` values

### Change refresh interval
In `UsageService.swift`, modify `refreshInterval` (default: 30 seconds)

### Add new scraped data fields
1. Add property to `UsageData.swift`
2. Update JavaScript in `UsageService.scrapeUsage(from:)` to extract new field
3. Update `MenuBarView.swift` to display new field

### Debug scraping issues
Click "Debug Info" in menu bar dropdown to see raw JavaScript output

## File Dependencies and Function Mappings

### Dependency Graph

```
ClaudeUsageMenuBarApp.swift
├── UsageService (state object)
├── WindowManager (state object)
├── MenuBarView (view)
│   ├── UsageService (environment object)
│   ├── WindowManager (environment object)
│   ├── AppConfig.shared (singleton)
│   ├── LabeledRow (component)
│   ├── ActionButton (component)
│   ├── UsageProgressBar (component)
│   └── DebugWindow (utility)
│       └── ClipboardHelper (helper)
└── AppDelegate (lifecycle)

WindowManager
└── UsageWebView (view)
    ├── UsageService (environment object)
    ├── WindowManager (environment object)
    └── ClaudeWebView (view)
        ├── UsageService (environment object)
        └── WebViewCoordinator (delegate)
            └── UsageService (reference)

UsageService
├── UsageData (model)
├── ScrapedUsageData (internal struct)
├── WeeklyCountdownCalculator (utility enum)
└── UsageScrapingScript (JavaScript enum)
```

### File-by-File Function Reference

#### ClaudeUsageMenuBarApp.swift
| Type | Function/Property | Called By | Calls |
|------|-------------------|-----------|-------|
| `ClaudeUsageMenuBarApp` | `body` | SwiftUI | `MenuBarView`, `usageService.displayText` |
| `AppDelegate` | `applicationDidFinishLaunching` | macOS | `NSApp.setActivationPolicy` |
| `WindowManager` | `openUsageWindow(usageService:)` | `MenuBarView` | `createWindow`, `NSApp.activate` |
| `WindowManager` | `closeUsageWindow()` | `UsageWebView` | `webViewWindow?.close` |
| `WindowManager` | `createWindow(usageService:)` | `openUsageWindow` | `UsageWebView`, `NSHostingView` |

#### UsageService.swift
| Type | Function/Property | Called By | Calls |
|------|-------------------|-----------|-------|
| `UsageService` | `init()` | App startup | `setupBackgroundWebView`, `startAutoRefresh`, `triggerRefresh` |
| `UsageService` | `triggerRefresh()` | Timer, UI buttons | `webView.load`, `setError` |
| `UsageService` | `logout()` | `MenuBarView` | `resetToLoggedOut` |
| `UsageService` | `setError(_:)` | Navigation failures | `resetCountdown` |
| `UsageService` | `setLoggedOut()` | `WebViewCoordinator` | `resetCountdown` |
| `UsageService` | `handleNavigationFinished(webView:)` | `WKNavigationDelegate` | `setLoggedOut`, `scrapeUsage` |
| `UsageService` | `scrapeUsage(from:)` | `handleNavigationFinished` | `evaluateJavaScript`, `handleScrapingResult` |
| `UsageService` | `handleScrapingResult(_:error:)` | JS callback | `setError`, `applyScrapedData` |
| `UsageService` | `applyScrapedData(_:)` | `handleScrapingResult` | `updateResetCountdowns`, `resetCountdown` |
| `UsageService` | `startAutoRefresh()` | `init` | `handleTimerTick` via Timer |
| `UsageService` | `handleTimerTick()` | Timer | `updateResetCountdowns`, `triggerRefresh` |
| `WeeklyCountdownCalculator` | `calculate(from:currentDate:)` | `updateResetCountdowns` | `extractWeekday`, `extractTime`, `calculateTargetDate`, `formatCountdown` |

#### MenuBarView.swift
| Type | Function/Property | Called By | Calls |
|------|-------------------|-----------|-------|
| `MenuBarView` | `body` | SwiftUI | `header`, `accountInfo`, `usageSection`, `statusSection`, `actionButtons` |
| `MenuBarView` | `usageSection(title:percentage:usage:resetTime:color:)` | `body` | `UsageProgressBar`, `LabeledRow`, `AppConfig.shared.gradientColors` |
| `ActionButton` | `body` | `actionButtons` | `action` closure |
| `DebugWindow` | `show(text:)` | "Show Debug Info" button | `ClipboardHelper` |
| `ClipboardHelper` | `copyToClipboard()` | Copy button | `NSPasteboard` |

#### WebViewCoordinator.swift
| Type | Function/Property | Called By | Calls |
|------|-------------------|-----------|-------|
| `WebViewCoordinator` | `webView(_:decidePolicyFor:decisionHandler:)` | WebKit | `isAllowedHost`, `NSWorkspace.shared.open` |
| `WebViewCoordinator` | `webView(_:didFinish:)` | WebKit | `usageService.triggerRefresh`, `usageService.setLoggedOut`, `redirectToUsagePage` |
| `WebViewCoordinator` | `isAllowedHost(_:)` | `decidePolicyFor` | - |
| `WebViewCoordinator` | `isAuthPage(_:)` | `didFinish` | - |
| `WebViewCoordinator` | `isClaudeMainPage(host:urlString:)` | `didFinish` | `isAuthPage` |
| `WebViewCoordinator` | `redirectToUsagePage(_:)` | `didFinish` | `webView.load` |

#### ClaudeWebView.swift
| Type | Function/Property | Called By | Calls |
|------|-------------------|-----------|-------|
| `ClaudeWebView` | `makeNSView(context:)` | SwiftUI | `WKWebView`, `webView.load` |
| `ClaudeWebView` | `makeCoordinator()` | SwiftUI | `WebViewCoordinator(usageService:)` |

#### UsageData.swift
| Type | Function/Property | Called By | Calls |
|------|-------------------|-----------|-------|
| `UsageData` | `displayPercentage` | `UsageService.displayText`, `MenuBarView` | - |
| `UsageData` | `usageDescription` | `MenuBarView` | - |
| `UsageData` | `weeklyUsageDescription` | `MenuBarView` | - |

#### AppConfig.swift
| Type | Function/Property | Called By | Calls |
|------|-------------------|-----------|-------|
| `AppConfig` | `colorForPercentage(_:)` | `MenuBarView` | - |
| `AppConfig` | `gradientColors(for:)` | `MenuBarView` | - |
| `AppConfig` | `saveToUserDefaults()` | (manual save) | `UserDefaults.standard.set` |
| `AppConfig` | `loadFromUserDefaults()` | `init` | `UserDefaults.standard` |

### Test Coverage

| Test File | Tests | Covers |
|-----------|-------|--------|
| `UsageDataTests.swift` | 11 | `UsageData` computed properties, default values |
| `ScrapedUsageDataTests.swift` | 16 | `UsageData` display formatting, state tests |
| `AppConfigTests.swift` | 8 | Color thresholds, gradient colors, default thresholds |
| `AppConfigEdgeCaseTests.swift` | 16 | Boundary conditions (exact thresholds), full range validation |
| `WeeklyCountdownCalculatorTests.swift` | 9 | Time parsing, day calculation, edge cases (12 AM/PM) |
| `WeeklyCountdownCalculatorDeterministicTests.swift` | 24 | Fixed-date tests, `extractWeekday`, `extractTime`, `formatCountdown` |
| `WebViewCoordinatorTests.swift` | 17 | OAuth domain whitelisting, auth page detection, main page detection |
| `RefreshTimeoutTests.swift` | 15 | Refresh timeout detection, recovery from stuck state, boundary conditions |

**Total: 117 tests**

## Verification Steps

After completing each change, run through these steps to confirm everything works:

```bash
# 1. Run tests
xcodebuild test -project ClaudeUsageMenuBar.xcodeproj -scheme ClaudeUsageMenuBar

# 2. Build the app
xcodebuild -project ClaudeUsageMenuBar.xcodeproj -scheme ClaudeUsageMenuBar -configuration Release build

# 3. Uninstall existing app
./uninstall.sh

# 4. Install fresh build
./install.sh

# 5. Confirm app is running
pgrep -x ClaudeUsageMenuBar && echo "App is running"
```

## First-Time User Flow

1. App launches as menu bar accessory (no Dock icon due to `LSUIElement=true`)
2. User clicks menu bar icon (CPU icon with "--" percentage)
3. Clicks "Open Usage Page / Login"
4. Web view window opens to `https://claude.ai/settings/usage`
5. User logs in via OAuth (Google, Microsoft, Apple, etc.)
6. `WebViewCoordinator` detects successful login, triggers refresh
7. `UsageService` scrapes page via JavaScript injection
8. Menu bar updates with actual percentage

## Troubleshooting

### App not appearing in menu bar
- Check Activity Monitor for "ClaudeUsageMenuBar" process
- Try `pkill ClaudeUsageMenuBar && open /Applications/ClaudeUsageMenuBar.app`

### Usage shows "--" after login
- Click "Refresh Now" button
- Check "Debug Info" for scraping errors
- Claude.ai page structure may have changed (update JavaScript in `UsageScrapingScript`)

### Login not working
- Verify OAuth provider is in `allowedHostSuffixes` (WebViewCoordinator.swift)
- Check network connectivity
- Try logging out and back in

### Build errors
- Clean build folder: `rm -rf ~/Library/Developer/Xcode/DerivedData/ClaudeUsageMenuBar-*`
- Ensure Xcode 14.0+ and macOS 13.0+ deployment target

## OAuth Providers Supported

The `WebViewCoordinator` whitelist includes:
- claude.ai, anthropic.com (main sites)
- google.com, googleapis.com, gstatic.com (Google OAuth)
- apple.com, icloud.com (Apple OAuth)
- microsoftonline.com, microsoft.com, live.com (Microsoft OAuth)
- okta.com, auth0.com (Enterprise SSO)
- clerk.dev, clerk.accounts.dev (Clerk auth)
