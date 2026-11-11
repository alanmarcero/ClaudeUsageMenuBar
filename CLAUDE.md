# CLAUDE.md - Project Notes

## Claude Code Login Source

When Claude Code is signed in on the Mac, the Claude provider skips the web page. `ClaudeCodeUsageAPI` (Services/ClaudeCodeUsageAPI.swift) reads Claude Code's saved OAuth login with `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w` and calls `GET https://api.anthropic.com/api/oauth/usage` with `anthropic-beta: oauth-2025-04-20`. It maps the response's `limits` rows (`session`, `weekly_all`, `weekly_scoped`) into the same fields the scraper fills.

- This exists because an SSO device-compliance check (Microsoft Entra) can block the claude.ai login in the embedded web view.
- The app never refreshes the login. A refresh replaces the token and signs Claude Code out. An expired login shows an error until Claude Code renews it.
- The `security` tool is used instead of `SecItemCopyMatching`: the item's access list trusts that tool, so no prompt shows, even after an update of this ad hoc signed app.
- With no Claude Code login, the provider falls back to the web scraping described below.

## Gemini Provider

When the Gemini / Antigravity CLI (`gemini` / `agy`) is signed in on the Mac, the Gemini provider (`UsageProvider.gemini`, `readsGeminiLogin: true`) skips the web page. `GeminiUsageAPI` (Services/GeminiUsageAPI.swift) reads the OAuth login saved by `go-keyring` with `/usr/bin/security find-generic-password -s "gemini" -w` (unwrapping `go-keyring-base64:` or `go-keyring-encoded:`) and calls `POST https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary` (with fallback to `cloudcode-pa.googleapis.com`) and `POST https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist` with `User-Agent: antigravity/cli/1.5.1 (aidev_client; os_type=darwin; arch=arm64; cl=1014269460; auth_method=consumer)`.

- Maps `gemini-5h` to `Session (Flash)` (`dailyPercentage`), `gemini-weekly` to `Weekly (Flash)` (`weeklyPercentage`), `gemini-argon-wtu-weekly` to `Weekly (Argon)` (`sonnetWeeklyPercentage`), `Weekly (Carbon)` (`carbonWeeklyPercentage`), `3p-5h` to `Session (Claude & GPT)` (`designDailyPercentage`), and `3p-weekly` to `Weekly (Claude & GPT)` (`designWeeklyPercentage`). When Carbon is not available on the account, it is grayed out and displayed as 0%.
- When the access token expires or nears expiration, GeminiUsageAPI automatically renews it via Google's OAuth endpoint (https://oauth2.googleapis.com/token) using the saved refresh_token, and writes the refreshed credentials back to Keychain under service "gemini" so the CLI stays in sync.
- Gemini's section starts with a "Menu bar" row (same control as Cursor's, shared `ProviderSection.menuMetricRow`) that picks Argon, Carbon, Opus (Claude & GPT), or Flash for the menu bar. `UsageProviders.geminiMenuBarMetricID` persists it (`geminiMenuBarMetricID`, default `argon`); picking one also selects Gemini. For Flash and Opus, the menu bar always displays their 5-hour session percentage; weekly usage is never displayed on the menu bar.
- The popover header drops the wrapping "Usage" title label, shows the version in the top left, and places the platform selector chips on the right.

## Cursor Provider

The Cursor provider (added in 2.0.0) loads `https://cursor.com/dashboard/spending` and its script (`CursorScrapingScript` in Models/UsageProvider.swift) calls `GET /api/usage-summary` same-origin from the signed-in page — the endpoint the dashboard itself uses. It maps `individualUsage.plan`: `totalPercentUsed` → Included (`percentage`), `apiPercentUsed` → Other Models (`weeklyPercentage`), `autoPercentUsed` → Cursor Models (`sonnetWeeklyPercentage`, full row title in `sonnetWeeklyLabel`). Do not use `used/limit` cents for Included: they are stale on two-pool plans (2000/2000 while the pools read 22%/3%) — that was the 2.0.3 fix; the cents ratio remains only as a fallback when `totalPercentUsed` is absent. All three reset at `billingCycleEnd`, formatted as an absolute "Resets …" string that the weekly countdown parses; `DailyCountdownCalculator` delegates absolute dates to the weekly calculator for the primary row. Cursor's pools are independent, so the provider sets `weeklyBlocksPrimary: false` (see `UsageData.weeklyBlocksPrimary`). A 401 from the API shows the log-in prompt; if the API stops answering, the script falls back to scraping the Spending page's pool labels. `membershipType` becomes the plan name. Since 2.0.2 it also maps `individualUsage.onDemand.used` (cents → dollars) to an On-demand row; a Team budget row added in 2.0.2 was removed in 2.0.4. Cursor has no redeemable resets, so no Resets row appears for it.

## Cursor Menu-Bar Metric

Cursor's section starts with a "Menu bar" row (2.1.1 as a floating square button, then a section-bottom row in 2.1.3, then directly under the Cursor header in 2.1.4) that picks which metric the menu bar shows while Cursor is selected: Other Models (`weeklyPercentage`), Cursor Models (`sonnetWeeklyPercentage`), On-demand (dollars), or Grok Bot (2.1.2). The Included total (`percentage`) lost its bar and its menu-bar slot in 2.1.6 — it is just the two pools combined; `ProviderSection` skips Cursor's primary row, the scraper still maps `totalPercentUsed` for the tooltip/debug data, and a saved "included" metric pick migrates to Other Models, which is also the default and the fallback when Grok Bot is hidden while chosen. Grok Bot is combined into Cursor overall: it has no top selector chip (`UsageProviders.selectorServices` excludes it), its weekly row renders inside the Cursor section (`GrokBotMetricRow`, via `sectionServices` folding — it only stands alone as a section when Cursor is hidden), and a saved Grok Bot menu-bar selection migrates to Cursor. `UsageProviders.cursorMenuBarMetricID` persists it (`cursorMenuBarMetricID`); picking a metric also selects Cursor as the menu-bar provider. `UsageProviders.menuBarDisplay(for:)` is the shared display string used by the status item and the Cursor header chip; other providers always return `displayPercentage`.

## Hiding Providers

The "Platforms" dropdown at the bottom of the popover — next to the More (…) menu since 2.1.5; it started as a submenu inside it in 2.1.0 — toggles providers on and off. `UsageProviders.hiddenProviderIDs` persists to UserDefaults (`hiddenProviderIDs`); hidden providers disappear from the sections, header chips, and tooltip, and their `UsageService.isRefreshPaused` stops polling (login and cached snapshot are kept; re-showing refreshes immediately). At least one provider must stay visible, and hiding the menu-bar-selected provider moves the selection to the first visible one.

## Grok Bot Provider

Grok Bot ("Sand" on the wire) is metered on the Cursor account, so the provider (added in 2.0.1) shares the Cursor session and loads `cursor.com/dashboard/bot`. `GrokBotScrapingScript` POSTs `/api/dashboard/get-sand-usage-status` (body `{}`, same-origin so the POST Origin header is automatic) and maps `usagePercent` onto the primary slot with the row labeled "Weekly" (`secondaryLabel: nil` hides the second row). An account with no Bot pool also answers 0%, so `hasNonZeroIncludedLimit`/`includedLimitZero` gate success and show "Your plan does not include Grok Bot usage." instead. camelCase and snake_case keys are both accepted. Logging out of Grok Bot clears Cursor records too — it is the same session.

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
├── ClaudeUsageMenuBarTests/         # 182 unit tests
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
- Auto-refreshes every 2 minutes (120 seconds) via background WKWebView or CLI OAuth APIs
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
| `refreshInterval` | 120s | Time between auto-refreshes (all providers) |
| `timerInterval` | 1.0s | Countdown tick interval |
| `initialRefreshDelay` | 2.0s | Delay before first refresh on launch |
| `scrapeDelay` | 2.0s | Delay after page load before scraping |
| `backgroundWebViewSize` | 1024x768 | Hidden webview dimensions |

### CacheMaintenance Constants (UsageService.swift)
| Constant | Value | Purpose |
|----------|-------|---------|
| `purgeEveryNRefreshes` | 30 | Successful refreshes between WebKit cache purges (~1 hour); also purges once on the first refresh after launch |
| `httpCacheDataTypes` | disk/memory/fetch cache | Data types purged — deliberately excludes cookies and storage |

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

Tests are in `ClaudeUsageMenuBarTests/` with **182 unit tests** covering core logic:

| Test File | Tests | Coverage |
|-----------|-------|----------|
| `AppConfigTests.swift` | 8 | Color threshold logic |
| `AppConfigEdgeCaseTests.swift` | 17 | Boundary conditions, full range coverage |
| `UsageDataTests.swift` | 25 | Display formatting, persistence (UsageCache), RelativeTime/isStale, UsageTooltip |
| `ScrapedUsageDataTests.swift` | 10 | UsageData model, state tests |
| `WeeklyCountdownCalculatorTests.swift` | 9 | Basic time parsing, day calculation |
| `WeeklyCountdownCalculatorDeterministicTests.swift` | 26 | Fixed-date tests for deterministic results |
| `DailyCountdownCalculatorTests.swift` | 7 | Clock-time and relative daily resets |
| `UsageProviderTests.swift` | 15 | Provider registry and Codex scraper fixtures |
| `WebViewCoordinatorTests.swift` | 23 | URL filtering, OAuth whitelisting, auth detection |
| `RefreshTimeoutTests.swift` | 15 | Refresh timeout detection, stuck-state recovery |
| `DiskPressureTests.swift` | 14 | Cache purge scheduling and data-type scope |
| `ClaudeCodeUsageAPITests.swift` | 13 | Claude Code login parsing, usage endpoint mapping, reset formatting |

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
In `UsageService.swift`, modify `refreshInterval` (default: 120 seconds)

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
│   ├── ProviderSection (component)
│   ├── IconButton (component)
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
| `MenuBarView` | `body` | SwiftUI | `header`, `ProviderSection`, `footer` |
| `MenuBarView` | `footer` / `moreMenu` | `body` | `refreshAll`, `SettingsWindow`, `DebugWindow`, `AboutWindow`, `checkForUpdates` |
| `ProviderSection` | `usageRow(_:_:_:)` | `body` | `UsageProgressBar`, `AppConfig.shared.gradientColors` |
| `IconButton` | `body` | provider header, footer | `action` closure |
| `DebugWindow` | `show(text:)` | "Show Debug Info" menu item | `ClipboardHelper` |
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
| `UsageDataTests.swift` | 25 | `UsageData` props, `UsageCache` persistence, `RelativeTime`/`isStale`, `UsageTooltip` |
| `ScrapedUsageDataTests.swift` | 10 | `UsageData` display formatting, state tests |
| `AppConfigTests.swift` | 8 | Color thresholds, gradient colors, default thresholds |
| `AppConfigEdgeCaseTests.swift` | 17 | Boundary conditions (exact thresholds), full range validation |
| `WeeklyCountdownCalculatorTests.swift` | 9 | Time parsing, day calculation, edge cases (12 AM/PM) |
| `WeeklyCountdownCalculatorDeterministicTests.swift` | 26 | Fixed-date tests, absolute dates, `extractWeekday`, `extractTime`, `formatCountdown` |
| `DailyCountdownCalculatorTests.swift` | 7 | Clock-time and relative daily resets |
| `UsageProviderTests.swift` | 15 | Provider registry and Codex scraper fixtures |
| `WebViewCoordinatorTests.swift` | 23 | OAuth domain whitelisting, auth page detection, main page detection |
| `RefreshTimeoutTests.swift` | 15 | Refresh timeout detection, recovery from stuck state, boundary conditions |
| `DiskPressureTests.swift` | 14 | `CacheMaintenance` purge interval, launch purge, data-type scope |
| `ClaudeCodeUsageAPITests.swift` | 13 | `ClaudeCodeUsageAPI` login parsing, `limits` mapping, expired login, `resetText` |

**Total: 182 tests**

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
3. Clicks the person icon ("Log in to Claude")
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
