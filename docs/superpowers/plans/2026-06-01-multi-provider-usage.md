# Multi-Provider Usage Tracking (Claude + Codex) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add OpenAI Codex usage tracking beside the existing Claude tracking, refactoring the app to be provider-agnostic (adding a provider = a descriptor + a scraping script), and ship it as v1.1.

**Architecture:** A `UsageProvider` value type fully describes a provider (URL, glyph, OAuth hosts, scraping script). The existing `UsageService` is parameterized by a `UsageProvider` (keeping the type name to preserve the existing test suite — one instance per provider satisfies the "generic per-provider service" design). A `UsageProviders` container owns one service per provider and re-publishes their changes so the menu bar label aggregates both. The menu bar shows both providers side by side; the dropdown renders one section per provider with per-provider login/logout.

**Tech Stack:** Swift, SwiftUI, WebKit, Combine, AppKit. Xcode manual `.pbxproj` membership (no synchronized groups — every new file needs explicit pbxproj entries). Sparkle for delivery.

---

## File Structure

**New files:**
- `ClaudeUsageMenuBar/Models/UsageProvider.swift` — provider descriptor + `.claude`/`.codex` registry + Codex scraping script.
- `ClaudeUsageMenuBar/Services/UsageProviders.swift` — `ObservableObject` container of per-provider `UsageService`s.
- `ClaudeUsageMenuBarTests/UsageProviderTests.swift` — registry validity tests.

**Modified files:**
- `ClaudeUsageMenuBar/Services/UsageService.swift` — parameterize by `UsageProvider`; move Claude scraping JS into `UsageProvider.claude`.
- `ClaudeUsageMenuBar/WebView/WebViewCoordinator.swift` — parameterize by provider.
- `ClaudeUsageMenuBar/WebView/ClaudeWebView.swift` — becomes `ProviderWebView`.
- `ClaudeUsageMenuBar/Views/UsageWebView.swift` — takes provider + service.
- `ClaudeUsageMenuBar/Views/MenuBarView.swift` — per-provider sections + `MenuBarLabel` + `ProviderSection`.
- `ClaudeUsageMenuBar/ClaudeUsageMenuBarApp.swift` — `UsageProviders` state object, per-provider window manager.
- `ClaudeUsageMenuBarTests/WebViewCoordinatorTests.swift` — Codex host tests; rename `isClaudeMainPage` → `isProviderMainPage`.
- `ClaudeUsageMenuBar.xcodeproj/project.pbxproj` — register new files; bump version.
- `ClaudeUsageMenuBar/Info.plist` — bump version.

**pbxproj ID scheme (continue the existing pattern):** app-target files use `001A0xxxx`, test-target files use `002A0xxxx`. New IDs reserved by this plan:
- `UsageProvider.swift`: buildFile `001A00080`, fileRef `001A00081`
- `UsageProviders.swift`: buildFile `001A00082`, fileRef `001A00083`
- `UsageProviderTests.swift`: buildFile `002A00080`, fileRef `002A00081`

---

## Task 1: `UsageProvider` descriptor + registry (Claude only first)

**Files:**
- Create: `ClaudeUsageMenuBar/Models/UsageProvider.swift`
- Create: `ClaudeUsageMenuBarTests/UsageProviderTests.swift`
- Modify: `ClaudeUsageMenuBar.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create `UsageProvider.swift` with the descriptor, shared SSO hosts, and the Claude registry entry.** The Claude scraping script is moved here from `UsageService.swift` verbatim (it currently lives in `enum UsageScrapingScript`). Paste the existing script string unchanged as `claudeScrapingScript`.

```swift
import Foundation

struct UsageProvider: Identifiable {
    let id: String
    let displayName: String
    let menuGlyph: String        // SF Symbol
    let primaryHost: String      // host whose non-usage pages redirect to usageURL
    let usageURL: URL
    let usagePathFragment: String
    let loginPaths: [String]
    let oauthHostSuffixes: [String]
    let dataRecordTokens: [String] // WKWebsiteDataStore display-name tokens to clear on logout
    let scrapingScript: String

    static let sharedSSOHosts = [
        "google.com", "googleapis.com", "gstatic.com",
        "apple.com", "icloud.com",
        "microsoftonline.com", "microsoft.com", "live.com",
        "okta.com", "auth0.com",
        "clerk.dev", "clerk.accounts.dev"
    ]

    static let claude = UsageProvider(
        id: "claude",
        displayName: "Claude",
        menuGlyph: "cpu.fill",
        primaryHost: "claude.ai",
        usageURL: URL(string: "https://claude.ai/settings/usage")!,
        usagePathFragment: "/settings/usage",
        loginPaths: ["/login", "/signin"],
        oauthHostSuffixes: ["claude.ai", "anthropic.com"] + sharedSSOHosts,
        dataRecordTokens: ["claude", "anthropic"],
        scrapingScript: claudeScrapingScript
    )

    static let codex = UsageProvider(
        id: "codex",
        displayName: "Codex",
        menuGlyph: "chevron.left.forwardslash.chevron.right",
        primaryHost: "chatgpt.com",
        usageURL: URL(string: "https://chatgpt.com/codex/cloud/settings/analytics")!,
        usagePathFragment: "/codex/cloud/settings/analytics",
        loginPaths: ["/login", "/auth/login", "/auth"],
        oauthHostSuffixes: ["chatgpt.com", "openai.com", "oaistatic.com", "oaiusercontent.com"] + sharedSSOHosts,
        dataRecordTokens: ["openai", "chatgpt", "oaistatic"],
        scrapingScript: codexScrapingScript
    )

    static let all: [UsageProvider] = [.claude, .codex]
}
```

> Note: `claudeScrapingScript` and `codexScrapingScript` are `private let` constants at file scope in this same file. `claudeScrapingScript` = the exact string currently in `UsageScrapingScript.script` (Task 2 removes the old enum). `codexScrapingScript` is created in Task 3 — for Step 1, add a temporary one-line placeholder `private let codexScrapingScript = ""` so the file compiles; Task 3 replaces it.

- [ ] **Step 2: Register both new files in `project.pbxproj`.** Make four edits:

(a) In `/* Begin PBXBuildFile section */` (after line `001A00014 ...UpdateService.swift in Sources...`):
```
		001A00080 /* UsageProvider.swift in Sources */ = {isa = PBXBuildFile; fileRef = 001A00081; };
		001A00082 /* UsageProviders.swift in Sources */ = {isa = PBXBuildFile; fileRef = 001A00083; };
		002A00080 /* UsageProviderTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 002A00081; };
```

(b) In `/* Begin PBXFileReference section */`:
```
		001A00081 /* UsageProvider.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UsageProvider.swift; sourceTree = "<group>"; };
		001A00083 /* UsageProviders.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UsageProviders.swift; sourceTree = "<group>"; };
		002A00081 /* UsageProviderTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = UsageProviderTests.swift; sourceTree = "<group>"; };
```

(c) In the `Models` group (`001A00033`) children add `001A00081 /* UsageProvider.swift */,`; in the `Services` group (`001A00034`) children add `001A00083 /* UsageProviders.swift */,`; in the `ClaudeUsageMenuBarTests` group (`002A00030`) children add `002A00081 /* UsageProviderTests.swift */,`.

(d) In the app `Sources` build phase (`001A00041`) `files` add:
```
				001A00080 /* UsageProvider.swift in Sources */,
				001A00082 /* UsageProviders.swift in Sources */,
```
and in the test `Sources` build phase (`002A00041`) `files` add:
```
				002A00080 /* UsageProviderTests.swift in Sources */,
```

> `UsageProviders.swift` and `UsageProviderTests.swift` are registered now but created in later tasks. Create empty stubs so the build doesn't break: `import Foundation` in `UsageProviders.swift`, and `import XCTest` + `@testable import ClaudeUsageMenuBar` + empty `final class UsageProviderTests: XCTestCase {}` in the test file. They are filled in Tasks 4 and 1-Step-3.

- [ ] **Step 3: Write the failing registry tests** in `UsageProviderTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageMenuBar

final class UsageProviderTests: XCTestCase {

    func testRegistryContainsClaudeAndCodex() {
        let ids = UsageProvider.all.map { $0.id }
        XCTAssertEqual(ids, ["claude", "codex"])
    }

    func testEachProviderHasNonEmptyScriptAndValidURL() {
        for provider in UsageProvider.all {
            XCTAssertFalse(provider.scrapingScript.isEmpty, "\(provider.id) script empty")
            XCTAssertEqual(provider.usageURL.absoluteString.isEmpty, false)
            XCTAssertTrue(provider.usagePathFragment.hasPrefix("/"))
        }
    }

    func testClaudeOAuthHostsIncludeSharedSSOAndOwnDomains() {
        let hosts = UsageProvider.claude.oauthHostSuffixes
        XCTAssertTrue(hosts.contains("claude.ai"))
        XCTAssertTrue(hosts.contains("anthropic.com"))
        XCTAssertTrue(hosts.contains("google.com"))
    }

    func testCodexOAuthHostsIncludeOpenAIAndSharedSSO() {
        let hosts = UsageProvider.codex.oauthHostSuffixes
        XCTAssertTrue(hosts.contains("chatgpt.com"))
        XCTAssertTrue(hosts.contains("openai.com"))
        XCTAssertTrue(hosts.contains("apple.com"))
    }
}
```

- [ ] **Step 4: Run tests, expect FAIL to PASS once script is moved.** Run:
```bash
xcodebuild test -project ClaudeUsageMenuBar.xcodeproj -scheme ClaudeUsageMenuBar -destination 'platform=macOS' 2>&1 | tail -20
```
Expected after Task 2 completes the script move: these 4 tests PASS. (Until then, `testEachProviderHasNonEmptyScriptAndValidURL` fails because the Codex script is the empty placeholder — that's expected; it passes after Task 3.)

- [ ] **Step 5: Commit**
```bash
git add ClaudeUsageMenuBar/Models/UsageProvider.swift ClaudeUsageMenuBarTests/UsageProviderTests.swift ClaudeUsageMenuBar/Services/UsageProviders.swift ClaudeUsageMenuBar.xcodeproj/project.pbxproj
git commit -m "Add UsageProvider descriptor and registry"
```

---

## Task 2: Parameterize `UsageService` by `UsageProvider`

**Files:**
- Modify: `ClaudeUsageMenuBar/Services/UsageService.swift`

- [ ] **Step 1: Move the Claude scraping script.** Cut the entire `enum UsageScrapingScript { static let script = """ ... """ }` block out of `UsageService.swift`. Paste its string body into `UsageProvider.swift` as `private let claudeScrapingScript = """ ... """` (the triple-quoted content is unchanged).

- [ ] **Step 2: Add the provider property and init.** At the top of `UsageService` add:
```swift
    let provider: UsageProvider

    init(provider: UsageProvider = .claude) {
        self.provider = provider
        super.init()
        setupBackgroundWebView()
        startAutoRefresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.initialRefreshDelay) { [weak self] in
            self?.triggerRefresh()
        }
    }
```
Delete the old `override init()`.

- [ ] **Step 3: Use the descriptor in `triggerRefresh`.** Replace the hardcoded URL:
```swift
        guard let webView = backgroundWebView else {
            setError("WebView not available")
            return
        }
        webView.load(URLRequest(url: provider.usageURL))
```

- [ ] **Step 4: Use the descriptor in `scrapeUsage`.** Replace `UsageScrapingScript.script` with `provider.scrapingScript`:
```swift
        webView.callAsyncJavaScript(
            provider.scrapingScript,
            arguments: [:],
            in: nil,
            in: .page
        ) { [weak self] result in
            ...
        }
```

- [ ] **Step 5: Generalize `handleNavigationFinished`.** Replace its body:
```swift
    private func handleNavigationFinished(webView: WKWebView) {
        guard let url = webView.url else { return }
        let urlString = url.absoluteString.lowercased()

        if provider.loginPaths.contains(where: { urlString.contains($0) }) {
            setLoggedOut()
            setError("Please log in via 'Open \(provider.displayName) / Login'")
            return
        }

        if urlString.contains(provider.usagePathFragment) {
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.scrapeDelay) { [weak self] in
                self?.scrapeUsage(from: webView)
            }
            return
        }

        if let host = url.host, host.hasSuffix(provider.primaryHost),
           !urlString.contains("/oauth"), !urlString.contains("/callback") {
            webView.load(URLRequest(url: provider.usageURL))
        }
    }
```

- [ ] **Step 6: Scope `logout` to the provider's data tokens.** Replace the filter:
```swift
            let claudeRecords = records.filter { record in
                provider.dataRecordTokens.contains { record.displayName.lowercased().contains($0) }
            }
            dataStore.removeData(ofTypes: dataTypes, for: claudeRecords) { [weak self] in
```

- [ ] **Step 7: Run the full existing suite to verify nothing regressed.** All existing tests construct `UsageService()` which now defaults to `.claude`, so they still compile and pass. Run:
```bash
xcodebuild test -project ClaudeUsageMenuBar.xcodeproj -scheme ClaudeUsageMenuBar -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: PASS (RefreshTimeoutTests, UsageProviderTests except Codex-script-empty until Task 3, etc.).

- [ ] **Step 8: Commit**
```bash
git add ClaudeUsageMenuBar/Services/UsageService.swift ClaudeUsageMenuBar/Models/UsageProvider.swift
git commit -m "Parameterize UsageService by UsageProvider"
```

---

## Task 3: Codex scraping script

**Files:**
- Modify: `ClaudeUsageMenuBar/Models/UsageProvider.swift`

- [ ] **Step 1: Replace the placeholder `codexScrapingScript`** with a diagnostics-rich script returning the shared result dict shape (`percentage`, `resetTime`, `weeklyPercentage`, `weeklyResetTime`, `email`, `planName`, `success`, `error`, `debug`). Modeled on Claude's generic extraction (progressbars + `% used` + reset regex); Sonnet/Design fields stay null.

```swift
private let codexScrapingScript = """
const result = {
    success: false,
    percentage: null,
    resetTime: null,
    weeklyPercentage: null,
    weeklyResetTime: null,
    sonnetWeeklyPercentage: null,
    sonnetWeeklyResetTime: null,
    designWeeklyPercentage: null,
    designWeeklyResetTime: null,
    email: null,
    orgName: null,
    planName: null,
    error: null,
    debug: ''
};

const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const logs = [];
const normalizeText = (v) => (v || '').replace(/\\s+/g, ' ').trim();

const parsePercentage = (value) => {
    if (value === null || value === undefined) return null;
    const m = String(value).match(/(\\d+(?:\\.\\d+)?)/);
    return m ? Math.round(Number(m[1])) : null;
};

const getProgressPercentage = (pb) => {
    const now = parsePercentage(pb.getAttribute('aria-valuenow'));
    if (now !== null) return now;
    const txt = parsePercentage(pb.getAttribute('aria-valuetext'));
    if (txt !== null) return txt;
    const fill = Array.from(pb.children).find(c => c.style && c.style.width);
    return fill ? parsePercentage(fill.style.width) : null;
};

const findResetText = (texts) => {
    const startsWithReset = texts.find(t => /^resets?\\b/i.test(t));
    if (startsWithReset) return startsWithReset;
    return texts.find(t => /\\b\\d+\\s*(?:days?|d|hours?|hrs?|hr|h|minutes?|mins?|min)\\b/i.test(t)) || null;
};

const pageHasUsage = () => {
    const t = document.body.innerText || '';
    return /%\\s*used/i.test(t) || document.querySelector('[role="progressbar"]') !== null;
};

try {
    for (let i = 0; i < 60; i++) {
        if (pageHasUsage()) break;
        await sleep(250);
    }

    const bodyText = document.body.innerText || '';
    const allTexts = Array.from(document.querySelectorAll('span,p,div,h1,h2,h3,h4'))
        .map(el => normalizeText(el.textContent))
        .filter(t => t && t.length <= 180);

    // Primary: ordered "% used" matches → daily, weekly.
    const percentMatches = [...bodyText.matchAll(/(\\d+(?:\\.\\d+)?)\\s*%\\s*used/gi)];
    if (percentMatches.length > 0) {
        result.percentage = Math.round(Number(percentMatches[0][1]));
        if (percentMatches[1]) result.weeklyPercentage = Math.round(Number(percentMatches[1][1]));
        logs.push(`Found ${percentMatches.length} "% used" matches`);
    }

    // Fallback: progressbars in document order.
    const progressbars = Array.from(document.querySelectorAll('[role="progressbar"]'));
    if (result.percentage === null && progressbars.length > 0) {
        const ordered = progressbars.map(getProgressPercentage).filter(p => p !== null);
        if (ordered[0] !== undefined) result.percentage = ordered[0];
        if (ordered[1] !== undefined) result.weeklyPercentage = ordered[1];
        logs.push(`Used ${ordered.length} progressbars in document order`);
    }

    result.resetTime = findResetText(allTexts);

    // Best-effort plan/email from visible text.
    const emailMatch = bodyText.match(/[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}/i);
    if (emailMatch) result.email = emailMatch[0];
    const planMatch = bodyText.match(/\\b(Plus|Pro|Team|Enterprise|Business|Free)\\b/);
    if (planMatch) result.planName = planMatch[0];

    const progressbarDiagnostics = progressbars.slice(0, 10).map((pb, i) => ({
        index: i,
        ariaValueNow: pb.getAttribute('aria-valuenow'),
        ariaValueText: pb.getAttribute('aria-valuetext'),
        ariaLabel: pb.getAttribute('aria-label'),
        nearbyText: normalizeText(pb.parentElement?.parentElement?.textContent || '').substring(0, 200)
    }));
    const headingDiagnostics = Array.from(document.querySelectorAll('h1,h2,h3,h4'))
        .map(h => normalizeText(h.textContent)).filter(Boolean).slice(0, 30);
    const percentUsedMatches = [...bodyText.matchAll(/[^\\n]{0,40}\\d+\\s*%\\s*used[^\\n]{0,40}/gi)]
        .map(m => normalizeText(m[0])).slice(0, 10);

    result.debug = JSON.stringify({
        percentage: result.percentage,
        weeklyPercentage: result.weeklyPercentage,
        resetTime: result.resetTime,
        email: result.email,
        planName: result.planName,
        progressbarCount: progressbars.length,
        progressbars: progressbarDiagnostics,
        headings: headingDiagnostics,
        percentUsedMatches,
        logs,
        url: location.href
    }, null, 2);

    result.success = result.percentage !== null || result.email !== null;
    if (!result.success) result.error = 'No Codex usage found. Logs: ' + logs.join(' | ');
} catch (e) {
    result.error = 'Script error: ' + e.message;
    result.debug += '\\nException: ' + e.stack;
}

return result;
"""
```

- [ ] **Step 2: Run the registry tests.** Run:
```bash
xcodebuild test -project ClaudeUsageMenuBar.xcodeproj -scheme ClaudeUsageMenuBar -destination 'platform=macOS' -only-testing:ClaudeUsageMenuBarTests/UsageProviderTests 2>&1 | tail -20
```
Expected: all 4 PASS (Codex script no longer empty).

- [ ] **Step 3: Commit**
```bash
git add ClaudeUsageMenuBar/Models/UsageProvider.swift
git commit -m "Add Codex scraping script (diagnostics-first)"
```

---

## Task 4: `UsageProviders` container

**Files:**
- Modify: `ClaudeUsageMenuBar/Services/UsageProviders.swift` (replace the stub)

- [ ] **Step 1: Implement the container.**
```swift
import Foundation
import Combine

@MainActor
final class UsageProviders: ObservableObject {
    let services: [UsageService]
    private var cancellables: Set<AnyCancellable> = []

    init(providers: [UsageProvider] = UsageProvider.all) {
        services = providers.map { UsageService(provider: $0) }
        for service in services {
            service.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    func refreshAll() {
        services.forEach { $0.triggerRefresh() }
    }

    var isAnyRefreshing: Bool {
        services.contains { $0.isRefreshing }
    }

    var nextRefreshCountdown: Int {
        services.map { $0.countdown }.min() ?? 0
    }

    var combinedDebugInfo: String {
        services
            .map { "=== \($0.provider.displayName) ===\n\($0.debugInfo)" }
            .joined(separator: "\n\n")
    }
}
```

- [ ] **Step 2: Build to verify it compiles.** Run:
```bash
xcodebuild -project ClaudeUsageMenuBar.xcodeproj -scheme ClaudeUsageMenuBar -configuration Release build 2>&1 | tail -15
```
Expected: BUILD SUCCEEDED (app still uses old single-service wiring; this type is not yet referenced — that's fine).

- [ ] **Step 3: Commit**
```bash
git add ClaudeUsageMenuBar/Services/UsageProviders.swift
git commit -m "Add UsageProviders aggregate container"
```

---

## Task 5: Parameterize `WebViewCoordinator`

**Files:**
- Modify: `ClaudeUsageMenuBar/WebView/WebViewCoordinator.swift`
- Modify: `ClaudeUsageMenuBarTests/WebViewCoordinatorTests.swift`

- [ ] **Step 1: Write/adjust the failing tests.** In `WebViewCoordinatorTests.swift`, change `setUp` to build a Claude coordinator explicitly and add a Codex one:
```swift
    var coordinator: WebViewCoordinator!
    var codexCoordinator: WebViewCoordinator!

    @MainActor
    override func setUp() {
        super.setUp()
        let claudeService = UsageService(provider: .claude)
        coordinator = WebViewCoordinator(usageService: claudeService, provider: .claude)
        let codexService = UsageService(provider: .codex)
        codexCoordinator = WebViewCoordinator(usageService: codexService, provider: .codex)
    }
```
Rename the three `isClaudeMainPage` test methods' calls to `isProviderMainPage`. Add:
```swift
    func testCodexCoordinatorAllowsOpenAIHosts() {
        XCTAssertTrue(codexCoordinator.isAllowedHost("chatgpt.com"))
        XCTAssertTrue(codexCoordinator.isAllowedHost("openai.com"))
        XCTAssertTrue(codexCoordinator.isAllowedHost("auth.openai.com"))
        XCTAssertTrue(codexCoordinator.isAllowedHost("accounts.google.com"))
    }

    func testCodexCoordinatorRejectsClaudeAndUnknownHosts() {
        XCTAssertFalse(codexCoordinator.isAllowedHost("claude.ai"))
        XCTAssertFalse(codexCoordinator.isAllowedHost("evil.com"))
    }

    func testProviderMainPageUsesProviderHost() {
        XCTAssertTrue(codexCoordinator.isProviderMainPage(host: "chatgpt.com", urlString: "https://chatgpt.com/"))
        XCTAssertFalse(codexCoordinator.isProviderMainPage(host: "claude.ai", urlString: "https://claude.ai/"))
    }
```

- [ ] **Step 2: Run, expect FAIL** (no `provider:` param, `isProviderMainPage` undefined). Run:
```bash
xcodebuild test -project ClaudeUsageMenuBar.xcodeproj -scheme ClaudeUsageMenuBar -destination 'platform=macOS' -only-testing:ClaudeUsageMenuBarTests/WebViewCoordinatorTests 2>&1 | tail -20
```
Expected: compile failure / FAIL.

- [ ] **Step 3: Parameterize the coordinator.** Edit `WebViewCoordinator`:
```swift
    private let usageService: UsageService
    private let provider: UsageProvider

    init(usageService: UsageService, provider: UsageProvider = .claude) {
        self.usageService = usageService
        self.provider = provider
    }
```
Replace the hardcoded `allowedHostSuffixes` array with the descriptor and delete the stored array:
```swift
    func isAllowedHost(_ host: String) -> Bool {
        provider.oauthHostSuffixes.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
```
Rename `isClaudeMainPage` → `isProviderMainPage` and use the provider host:
```swift
    func isProviderMainPage(host: String, urlString: String) -> Bool {
        let isPrimary = host == provider.primaryHost || host == "www.\(provider.primaryHost)"
        return isPrimary && !isAuthPage(urlString)
    }
```
In `didFinish`, replace `/settings/usage` with the descriptor:
```swift
        if urlString.contains(provider.usagePathFragment) {
            Task { @MainActor in
                usageService.triggerRefresh()
            }
        }
```

- [ ] **Step 4: Run, expect PASS.** Run the same `-only-testing:ClaudeUsageMenuBarTests/WebViewCoordinatorTests` command. Expected: PASS.

- [ ] **Step 5: Commit**
```bash
git add ClaudeUsageMenuBar/WebView/WebViewCoordinator.swift ClaudeUsageMenuBarTests/WebViewCoordinatorTests.swift
git commit -m "Parameterize WebViewCoordinator by provider"
```

---

## Task 6: `ProviderWebView` + `UsageWebView` + multi-window `WindowManager`

**Files:**
- Modify: `ClaudeUsageMenuBar/WebView/ClaudeWebView.swift`
- Modify: `ClaudeUsageMenuBar/Views/UsageWebView.swift`
- Modify: `ClaudeUsageMenuBar/ClaudeUsageMenuBarApp.swift` (WindowManager only in this task)

- [ ] **Step 1: Convert `ClaudeWebView` to `ProviderWebView`.** Replace the contents of `ClaudeWebView.swift`:
```swift
import SwiftUI
import WebKit

struct ProviderWebView: NSViewRepresentable {
    let provider: UsageProvider
    let service: UsageService

    func makeNSView(context: Context) -> WKWebView {
        let webView = ClaudeWebViewFactory.makeWebView()
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: provider.usageURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(usageService: service, provider: provider)
    }
}
```

- [ ] **Step 2: Update `UsageWebView` to take a provider + service.**
```swift
import SwiftUI

struct UsageWebView: View {
    let provider: UsageProvider
    @ObservedObject var service: UsageService
    @EnvironmentObject var windowManager: WindowManager

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ProviderWebView(provider: provider, service: service)
        }
    }

    private var toolbar: some View {
        HStack {
            Button(action: { service.triggerRefresh() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(service.isRefreshing)

            Spacer()
            Text("\(provider.displayName) Usage").font(.headline)
            Spacer()

            Button("Done") { windowManager.closeUsageWindow(provider: provider) }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
}
```

- [ ] **Step 3: Make `WindowManager` key windows by provider id.** In `ClaudeUsageMenuBarApp.swift` replace the `WindowManager` class:
```swift
@MainActor
class WindowManager: NSObject, ObservableObject, NSWindowDelegate {
    private var windows: [String: NSWindow] = [:]

    func openUsageWindow(provider: UsageProvider, service: UsageService) {
        if let existing = windows[provider.id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = createWindow(provider: provider, service: service)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        windows[provider.id] = window
    }

    func closeUsageWindow(provider: UsageProvider) {
        windows[provider.id]?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        windows = windows.filter { $0.value !== closing }
    }

    private func createWindow(provider: UsageProvider, service: UsageService) -> NSWindow {
        let contentView = UsageWebView(provider: provider, service: service)
            .environmentObject(self)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(provider.displayName) Usage"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        return window
    }
}
```

- [ ] **Step 4: Build.** (The `MenuBarExtra` body still references the old single-service API and will fail to build until Task 7. To keep this task independently committable, temporarily leave the `MenuBarExtra` using a single `UsageService` is NOT possible after the WindowManager change — so Task 6 and Task 7 are committed together.) Proceed directly to Task 7, then build once. Skip the standalone build here.

- [ ] **Step 5: Stage (do not commit yet — combined with Task 7).**
```bash
git add ClaudeUsageMenuBar/WebView/ClaudeWebView.swift ClaudeUsageMenuBar/Views/UsageWebView.swift ClaudeUsageMenuBar/ClaudeUsageMenuBarApp.swift
```

---

## Task 7: `MenuBarView` per-provider sections + `MenuBarLabel`

**Files:**
- Modify: `ClaudeUsageMenuBar/ClaudeUsageMenuBarApp.swift` (App scene + label)
- Modify: `ClaudeUsageMenuBar/Views/MenuBarView.swift`

- [ ] **Step 1: Update the App scene to use `UsageProviders` and a `MenuBarLabel`.** In `ClaudeUsageMenuBarApp.swift` replace the `@StateObject private var usageService` line and the scene body:
```swift
@main
struct ClaudeUsageMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var providers = UsageProviders()
    @StateObject private var updateService = UpdateService()
    @StateObject private var windowManager = WindowManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(providers)
                .environmentObject(updateService)
                .environmentObject(windowManager)
        } label: {
            MenuBarLabel(providers: providers)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var providers: UsageProviders

    var body: some View {
        HStack(spacing: 8) {
            ForEach(providers.services, id: \.provider.id) { service in
                HStack(spacing: 3) {
                    Image(systemName: service.provider.menuGlyph)
                    Text(service.usageData.displayPercentage).monospacedDigit()
                }
            }
        }
    }
}
```

- [ ] **Step 2: Rewrite `MenuBarView` for multiple providers.** Replace `MenuBarView` (keep `LabeledRow`, `ActionButton`, `UsageProgressBar`, `DebugWindow`, `ClipboardHelper` unchanged at the bottom of the file). New `MenuBarView` + new `ProviderSection`:
```swift
struct MenuBarView: View {
    @EnvironmentObject var providers: UsageProviders
    @EnvironmentObject var updateService: UpdateService
    @EnvironmentObject var windowManager: WindowManager

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(providers.services, id: \.provider.id) { service in
                Divider().padding(.horizontal, 16)
                ProviderSection(service: service)
                    .environmentObject(windowManager)
            }
            statusSection
            Divider().padding(.horizontal, 12)
            globalButtons
        }
        .frame(width: 280)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Usage").font(.headline).fontWeight(.semibold)
            Text("v\(appVersion)").font(.caption2).foregroundColor(.secondary)
            Spacer()
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 16, height: 16)
                .opacity(providers.isAnyRefreshing ? 1 : 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var statusSection: some View {
        HStack {
            Text("Refresh in \(providers.nextRefreshCountdown)s")
                .font(.caption).foregroundColor(.secondary).monospacedDigit()
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var globalButtons: some View {
        VStack(spacing: 4) {
            ActionButton(label: "Refresh All Now", isLoading: providers.isAnyRefreshing, disabled: providers.isAnyRefreshing) {
                providers.refreshAll()
            }
            ActionButton(label: "Show Debug Info") {
                DebugWindow.show(text: providers.combinedDebugInfo)
            }
            ActionButton(label: "Check for Updates...", disabled: !updateService.canCheckForUpdates) {
                updateService.checkForUpdates()
            }
            ActionButton(label: "Clear Cache") {
                providers.services.forEach { $0.clearCache() }
            }
            Divider().padding(.horizontal, 12).padding(.vertical, 4)
            ActionButton(label: "Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 8)
    }
}

struct ProviderSection: View {
    @ObservedObject var service: UsageService
    @EnvironmentObject var windowManager: WindowManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: service.provider.menuGlyph)
                Text(service.provider.displayName).font(.subheadline).fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 10)

            LabeledRow(label: "Email", value: service.usageData.email ?? "--")
                .padding(.horizontal, 16).padding(.top, 4)

            usageRow("Daily", service.usageData.percentage, service.dailyResetCountdown)
            usageRow("Weekly", service.usageData.weeklyPercentage, service.weeklyResetCountdown)
            if service.usageData.sonnetWeeklyPercentage != nil {
                usageRow("Weekly (Sonnet)", service.usageData.sonnetWeeklyPercentage, service.sonnetWeeklyResetCountdown)
            }
            if service.usageData.designWeeklyPercentage != nil {
                usageRow("Weekly (Design)", service.usageData.designWeeklyPercentage, service.designWeeklyResetCountdown)
            }

            if let error = service.usageData.errorMessage {
                HStack(alignment: .top) {
                    Text(error).font(.caption).foregroundColor(.orange).lineLimit(3)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
            }

            ActionButton(label: "Open \(service.provider.displayName) / Login") {
                windowManager.openUsageWindow(provider: service.provider, service: service)
            }
            ActionButton(label: service.usageData.isLoggedIn ? "Log Out of \(service.provider.displayName)" : "Log In to \(service.provider.displayName)") {
                if service.usageData.isLoggedIn {
                    service.logout()
                } else {
                    windowManager.openUsageWindow(provider: service.provider, service: service)
                }
            }
        }
        .padding(.bottom, 6)
    }

    private func usageRow(_ title: String, _ percentage: Int?, _ resetTime: String?) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.subheadline).fontWeight(.medium)
                Spacer()
                Text(percentage.map { "\($0)%" } ?? "--")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(percentage != nil ? AppConfig.shared.colorForPercentage(percentage) : .secondary)
            }
            if let pct = percentage {
                UsageProgressBar(percentage: pct, colors: AppConfig.shared.gradientColors(for: pct))
            }
            if let reset = resetTime {
                LabeledRow(label: "Resets in", value: reset)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}
```

- [ ] **Step 3: Build and run the full suite.** Run:
```bash
xcodebuild -project ClaudeUsageMenuBar.xcodeproj -scheme ClaudeUsageMenuBar -configuration Release build 2>&1 | tail -15
xcodebuild test -project ClaudeUsageMenuBar.xcodeproj -scheme ClaudeUsageMenuBar -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED and all tests PASS.

- [ ] **Step 4: Commit Tasks 6 + 7 together** (staged files from Task 6 plus these):
```bash
git add ClaudeUsageMenuBar/ClaudeUsageMenuBarApp.swift ClaudeUsageMenuBar/Views/MenuBarView.swift
git commit -m "Render both providers in menu bar label and dropdown"
```

---

## Task 8: Full validation + manual smoke test

**Files:** none (validation only)

- [ ] **Step 1: Run the required validation sequence (per CLAUDE.md).**
```bash
xcodebuild test -project ClaudeUsageMenuBar.xcodeproj -scheme ClaudeUsageMenuBar -destination 'platform=macOS' 2>&1 | tail -20
xcodebuild -project ClaudeUsageMenuBar.xcodeproj -scheme ClaudeUsageMenuBar -configuration Release build 2>&1 | tail -10
pkill -x ClaudeUsageMenuBar; sleep 1; ./install.sh
```
Expected: tests PASS, BUILD SUCCEEDED, app relaunches.

- [ ] **Step 2: Manual smoke test.** Open the menu bar dropdown: confirm two provider sections (Claude, Codex) each with their own Login button; the menu bar label shows two glyph+percent pairs. Log in to Codex via "Open Codex / Login", then click "Show Debug Info" and capture the Codex JSON block. Per the repo's diagnostics-first workflow, if Codex percentages are null, refine `codexScrapingScript` selectors using that real Debug Info and re-run Tasks 3 + 8.

---

## Task 9: Code-quality pass on the whole repo

**Files:** as needed per findings

- [ ] **Step 1: Run `/code-quality` on the whole repo** (user instruction). Invoke the `code-quality` skill scoped to the full repository.

- [ ] **Step 2: Fix every reported issue.** Apply all recommended changes. Keep changes behavior-preserving; re-run the full test suite after fixes:
```bash
xcodebuild test -project ClaudeUsageMenuBar.xcodeproj -scheme ClaudeUsageMenuBar -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: PASS.

- [ ] **Step 3: Commit**
```bash
git add -A
git commit -m "Apply code-quality fixes across repo"
```

---

## Task 10: Release v1.1

**Files:**
- Modify: `ClaudeUsageMenuBar/Info.plist`, `ClaudeUsageMenuBar.xcodeproj/project.pbxproj`

Follow the `release-cut` procedure. New version: `1.1`, build number `5` (current is `4`).

- [ ] **Step 1: Bump all version spots.**
```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.1" ClaudeUsageMenuBar/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 5" ClaudeUsageMenuBar/Info.plist
sed -i.bak -e 's/MARKETING_VERSION = 1.0.3;/MARKETING_VERSION = 1.1;/g' \
           -e 's/CURRENT_PROJECT_VERSION = 4;/CURRENT_PROJECT_VERSION = 5;/g' \
           ClaudeUsageMenuBar.xcodeproj/project.pbxproj
rm -f ClaudeUsageMenuBar.xcodeproj/project.pbxproj.bak
```
Verify: `grep -c "MARKETING_VERSION = 1.1;" ClaudeUsageMenuBar.xcodeproj/project.pbxproj` → 4; `grep -c "CURRENT_PROJECT_VERSION = 5;" ...` → 4.

- [ ] **Step 2: Re-validate and confirm installed version.**
```bash
xcodebuild test -project ClaudeUsageMenuBar.xcodeproj -scheme ClaudeUsageMenuBar -destination 'platform=macOS' 2>&1 | tail -5
pkill -x ClaudeUsageMenuBar; sleep 1; ./install.sh
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" /Applications/ClaudeUsageMenuBar.app/Contents/Info.plist
```
Expected: prints `1.1`.

- [ ] **Step 3: Commit + push to main** (scrubbed identity).
```bash
git add ClaudeUsageMenuBar/Info.plist ClaudeUsageMenuBar.xcodeproj/project.pbxproj
git -c user.name='alanmarcero' -c user.email='alanmarcero@users.noreply.github.com' commit -m "Bump version to 1.1"
# merge the feature branch to main if working on a branch, then:
git push origin main
```

- [ ] **Step 4: Build Sparkle artifacts.**
```bash
bash scripts/build-sparkle-update.sh
ls dist/
```
Expected: `dist/ClaudeUsageMenuBar-1.1.zip` and `dist/appcast.xml`.

- [ ] **Step 5: Create the GitHub release (zip + appcast both as assets).**
```bash
gh release create v1.1 --repo alanmarcero/ClaudeUsageMenuBar --target main \
  --title "v1.1" \
  --notes "Add Codex usage tracking alongside Claude; provider-agnostic refactor." \
  dist/ClaudeUsageMenuBar-1.1.zip dist/appcast.xml
```

- [ ] **Step 6: Verify the Sparkle feed resolves to v1.1.**
```bash
curl -sIL https://github.com/alanmarcero/ClaudeUsageMenuBar/releases/latest/download/appcast.xml | grep -i "location\|HTTP/"
```
Expected: 302 redirect to the `v1.1` tag's `appcast.xml`. If it points at an old tag, run `gh release list` and ensure v1.1 is marked Latest.

---

## Self-Review Notes

- **Spec coverage:** descriptor (Task 1), generic service (Task 2), Codex script (Task 3), aggregate container (Task 4), coordinator (Task 5), web views/windows (Task 6), menu bar both-side-by-side + per-provider login/logout (Task 7), validation (Task 8), code-quality (Task 9, per user), release v1.1 (Task 10, per user). All covered.
- **Naming consistency:** type stays `UsageService(provider:)`; coordinator `init(usageService:provider:)`; `isClaudeMainPage` → `isProviderMainPage` (updated in tests); `ClaudeWebView` → `ProviderWebView`; `WindowManager.openUsageWindow(provider:service:)` / `closeUsageWindow(provider:)`.
- **Deviation from spec:** spec named the generic service `ProviderUsageService`; plan keeps `UsageService` parameterized by a default-`.claude` provider to preserve the existing test suite without churn. Same architecture (one instance per provider), lower risk.
