# Multi-Provider Usage Tracking (Claude + Codex)

**Date:** 2026-06-01
**Status:** Approved for implementation
**Target version:** 1.1 (deploy to `main` via Sparkle on completion)

## Goal

Add OpenAI **Codex** usage tracking alongside the existing Claude tracking, and
"horizontally scale" the app so it is provider-agnostic: adding a future provider
is "add a descriptor + a scraping script," not a code fork.

Codex usage source: `https://chatgpt.com/codex/cloud/settings/analytics#usage`.
Confirmed by the user to expose a **percentage + reset** shape, mirroring Claude,
so it maps cleanly onto the existing `UsageData` model.

## Decisions (from brainstorming)

- **Menu bar label:** both providers side by side (glyph + percentage each).
- **Codex data shape:** percentage + reset, like Claude.
- **Architecture:** Provider descriptor + generic per-provider service (chosen over
  a cloned `CodexService` and over a single multi-provider orchestrator). This is
  the only option that is genuinely provider-agnostic, preserves single
  responsibility (one service = one provider), and reuses the hardened
  timer/refresh/recovery logic instead of duplicating it.
- **Login/logout:** per-provider buttons, each reflecting that provider's state.
- **Release:** cut v1.1 to `main` after full validation.

## Architecture

### 1. `UsageProvider` descriptor — `Models/UsageProvider.swift` (new)

A value type that fully describes a provider, making the rest of the app generic.

```swift
struct UsageProvider: Identifiable {
    let id: String                  // "claude", "codex"
    let displayName: String         // "Claude", "Codex"
    let menuGlyph: String           // SF Symbol
    let usageURL: URL
    let usagePathFragment: String   // "/settings/usage" | "/codex/cloud/settings/analytics"
    let loginPaths: [String]        // logged-out detection, e.g. ["/login","/signin","/auth"]
    let oauthHostSuffixes: [String] // navigation whitelist for this provider
    let scrapingScript: String      // provider-specific JS (returns the shared result dict)
}
```

Registry on the type:
- `UsageProvider.claude` — glyph `cpu.fill`, url `https://claude.ai/settings/usage`,
  fragment `/settings/usage`, hosts `claude.ai` + `anthropic.com` + shared SSO.
- `UsageProvider.codex` — glyph `chevron.left.forwardslash.chevron.right`,
  url `https://chatgpt.com/codex/cloud/settings/analytics`,
  fragment `/codex/cloud/settings/analytics`,
  hosts `chatgpt.com` + `openai.com` + `oaistatic.com` + shared SSO.
- `UsageProvider.all = [.claude, .codex]`.
- A shared SSO host list (`google.com`, `googleapis.com`, `gstatic.com`,
  `apple.com`, `icloud.com`, `microsoftonline.com`, `microsoft.com`, `live.com`,
  `okta.com`, `auth0.com`, `clerk.dev`, `clerk.accounts.dev`) is reused by both.

### 2. `ProviderUsageService` — generalized from `UsageService`

Today's `UsageService` is renamed/parameterized to `ProviderUsageService(provider:)`.
All existing logic is reused verbatim:
- hidden `WKWebView` setup, 30s auto-refresh, 1s countdown tick
- `triggerRefresh` / stuck-refresh timeout + recovery
- `scrapeUsage` / `handleScrapingResult` / `applyScrapedData`
- reset-countdown updates via `WeeklyCountdownCalculator`
- `logout` / `clearCache` (logout filters website data by the provider's hosts)

The only changes: `usageURL`, `scrapingScript`, `loginPaths`, and
`usagePathFragment` are read from the injected descriptor rather than hardcoded.
Each instance owns its own WebView/session and publishes its own `UsageData` and
countdowns. Provider identity is exposed (`var provider: UsageProvider`) for the UI.

`logout` scopes its data-record filter to the provider's host suffixes so logging
out of Codex does not clear the Claude session, and vice versa.

### 3. `UsageProviders` container — `Services/UsageProviders.swift` (new)

`@MainActor final class UsageProviders: ObservableObject`:
- Creates one `ProviderUsageService` per `UsageProvider.all` descriptor.
- Exposes `let services: [ProviderUsageService]`.
- In `init`, subscribes to each service's `objectWillChange` and forwards via its
  own `objectWillChange.send()`, storing the `AnyCancellable`s. This makes the
  container a faithful aggregate observable so the menu bar **label** (which reads
  all providers) re-renders on any child change.
- Convenience: `refreshAll()`, `combinedDebugInfo` (concatenated per-provider debug).

The app holds a single `@StateObject var providers = UsageProviders()`.

### 4. Menu bar label — both side by side

In `ClaudeUsageMenuBarApp`, the `MenuBarExtra` label observes `providers` and renders
an `HStack` over `providers.services`: each shows `Image(systemName: glyph)` +
`Text(service.usageData.displayPercentage)` (monospaced). Logged-out → `--`.

### 5. `MenuBarView` — one section per provider

`ForEach(providers.services)` renders a `ProviderSection` view that takes
`@ObservedObject var service: ProviderUsageService` (granular per-provider updates):
- provider name header + email row
- daily + weekly sections (existing `usageSection`), plus Sonnet/Design sections
  which remain Claude-only and stay hidden when their percentage is nil
- per-provider "Open <Provider> / Login" and "Log Out"/"Log In" rows driven by that
  service's `isLoggedIn`

Global rows stay shared at the bottom: Refresh (calls `providers.refreshAll()`),
Show Debug Info (`providers.combinedDebugInfo`), Check for Updates, Clear Cache, Quit.
Header (title + version + refreshing spinner) is unchanged; the spinner shows if any
service is refreshing.

### 6. WebView wiring

- `WebViewCoordinator` takes a `UsageProvider` and uses its `oauthHostSuffixes`
  (instead of the hardcoded `allowedHostSuffixes`) and `usagePathFragment` (instead
  of the hardcoded `/settings/usage`) in `didFinish`. `isAllowedHost`,
  `isAuthPage`, and `isClaudeMainPage` (renamed `isProviderMainPage`) generalize.
- `ClaudeWebView` → `ProviderWebView`: takes `provider` + its `service`, creates the
  WebView pointed at `provider.usageURL`, and builds the coordinator with the provider.
- `WindowManager.openUsageWindow(provider:service:)` keys windows by `provider.id` in
  a `[String: NSWindow]` dictionary so Claude and Codex login windows are independent.
  `windowWillClose` removes the matching entry.

### 7. Codex scraping script

Modeled on Claude's generic extraction path (progressbars + `% used` text + reset
regex). Returns the **same result dict keys** so `handleScrapingResult` is unchanged
(`percentage`, `resetTime`, `weeklyPercentage`, `weeklyResetTime`, `email`,
`planName`, `success`, `error`, `debug`; Sonnet/Design omitted/null for Codex).
It is diagnostics-rich (dumps headings, progressbar aria values, `% used` matches,
url into `debug`).

Constraint: the authenticated Codex page cannot be browsed from this environment
(matches the existing Playwright-denied gotcha for claude.ai). We ship a best-effort
script and refine label/selector specifics from the user's real Debug Info JSON after
first Codex login — diagnostics-first, the established workflow for this repo.

### 8. Data model

`UsageData` is unchanged. It already holds the daily/weekly/Sonnet/Design superset;
Codex fills daily + weekly and leaves Sonnet/Design nil (sections auto-hide).

## Testing

- Existing tests adapt to `ProviderUsageService(provider: .claude)`; all stay green
  (`RefreshTimeoutTests`, etc.).
- New `UsageProviderTests`: registry contains `.claude` and `.codex`; each has a
  non-empty script, a valid `usageURL`, and host lists that include the shared SSO
  hosts plus the provider's own domains.
- `WebViewCoordinatorTests` parameterized per provider: Codex coordinator allows
  `chatgpt.com`/`openai.com`, denies an unrelated host; Claude coordinator unchanged.
- Codex login-state detection: a `chatgpt.com/auth/login` URL is treated as
  logged-out for the Codex provider.

## Validation & Release

After implementation, run the project's required validation:

```bash
xcodebuild test -project ClaudeUsageMenuBar.xcodeproj -scheme ClaudeUsageMenuBar -destination 'platform=macOS'
xcodebuild -project ClaudeUsageMenuBar.xcodeproj -scheme ClaudeUsageMenuBar -configuration Release build
pkill -x ClaudeUsageMenuBar; sleep 1; ./install.sh
```

Then cut **v1.1** via the Sparkle release procedure: bump the version in all spots,
produce the signed build, `gh release create` with both the zip and `appcast.xml`,
and verify the "latest" redirect resolves.

## Out of Scope (YAGNI)

- A third provider (the architecture supports it, but none is being added now).
- Per-provider color-threshold customization (shared `AppConfig` thresholds apply).
- Combining the two login windows into a tabbed UI (per-provider windows chosen).
