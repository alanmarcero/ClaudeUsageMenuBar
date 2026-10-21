import XCTest
import WebKit
@testable import ClaudeUsageMenuBar

final class UsageProviderTests: XCTestCase {

    func testRegistryContainsClaudeAndCodex() {
        let ids = UsageProvider.all.map { $0.id }
        XCTAssertEqual(ids, ["claude", "codex"])
    }

    func testEachProviderHasNonEmptyScriptAndValidURL() {
        XCTAssertEqual(UsageProvider.all.count, 2)
        UsageProvider.all.forEach { provider in
            XCTAssertFalse(provider.scrapingScript.isEmpty, "\(provider.id) script empty")
            XCTAssertFalse(provider.usageURL.absoluteString.isEmpty, "\(provider.id) url empty")
            XCTAssertTrue(provider.usageURL.absoluteString.contains(provider.usagePathFragment), "\(provider.id) fragment")
        }
    }

    func testCodexFragmentMatchesHashRedirect() {
        XCTAssertTrue("https://chatgpt.com/?mweb_fallback=1#settings/usage".contains(UsageProvider.codex.usagePathFragment))
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

    @MainActor
    func testCodexWeeklyLimitWithResetBeforePercentLeft() async throws {
        let result = try await scrapeCodexFixture("""
        <div><div>Weekly limit</div><div><span>Resets in 7d 0h</span><span>100% left</span></div></div>
        <div>Usage limit resets</div>
        <div>Use a reset to restore your 5-hour limit, weekly limit, or both</div>
        <div>Full reset Expires Oct 22 at 5:12 PM EDT Use reset</div>
        <div>Weekly limits Period % of limit used Sep 29 – Oct 6 44.5%</div>
        """)

        XCTAssertEqual(result["weeklyPercentage"] as? Int, 0)
        XCTAssertEqual(result["weeklyResetTime"] as? String, "Resets in 7d 0h")
        XCTAssertTrue(result["percentage"] is NSNull)
        XCTAssertTrue(result["resetTime"] is NSNull)
        XCTAssertEqual(result["success"] as? Bool, true)
    }

    @MainActor
    func testCodexNewLimitCardsKeepPercentagesAndResetsSeparate() async throws {
        let result = try await scrapeCodexFixture("""
        <div><span>5-hour limit</span><span>Resets in 4h 12m</span><span>91% left</span></div>
        <div><span>Weekly limit</span><span>Resets in 6d 2h</span><span>22% left</span></div>
        """)

        XCTAssertEqual(result["percentage"] as? Int, 9)
        XCTAssertEqual(result["resetTime"] as? String, "Resets in 4h 12m")
        XCTAssertEqual(result["weeklyPercentage"] as? Int, 78)
        XCTAssertEqual(result["weeklyResetTime"] as? String, "Resets in 6d 2h")
    }

    @MainActor
    func testCodexReadsLimitCardsInInactiveOverviewTab() async throws {
        let result = try await scrapeCodexFixture("""
        <div hidden><div><span>Weekly limit</span><span>Resets in 7d 0h</span><span>100% left</span></div></div>
        <div>Usage history</div><div>Weekly limits Period % of limit used Sep 29 – Oct 6 44.5%</div>
        """)

        XCTAssertEqual(result["weeklyPercentage"] as? Int, 0)
        XCTAssertEqual(result["weeklyResetTime"] as? String, "Resets in 7d 0h")
    }

    @MainActor
    func testCodexWaitsForCurrentLimitDespiteHistoricalPercentages() async throws {
        let result = try await scrapeCodexFixture("""
        <div>Weekly limits Period % of limit used Sep 29 – Oct 6 44.5%</div>
        <div id="limit">Loading usage data…</div>
        <script>
          window.showCurrentLimit = () => {
            setTimeout(() => {
              document.getElementById('limit').innerHTML =
                '<div>Weekly usage limit</div><div>22% remaining</div><div>Resets in 6d 2h</div>';
            }, 500);
          };
        </script>
        """, beforeScrape: "window.showCurrentLimit()")

        XCTAssertEqual(result["weeklyPercentage"] as? Int, 78)
        XCTAssertEqual(result["weeklyResetTime"] as? String, "Resets in 6d 2h")
    }

    @MainActor
    func testCodexWeeklyOnlyFixtureDoesNotPopulateDaily() async throws {
        let result = try await scrapeCodexFixture("""
        <div>
          <div>Weekly usage limit</div>
          <div>22% remaining</div>
          <div>Resets Aug 31, 2026 9:01 AM</div>
        </div>
        """)

        XCTAssertTrue(result["percentage"] is NSNull)
        XCTAssertTrue(result["resetTime"] is NSNull)
        XCTAssertEqual(result["weeklyPercentage"] as? Int, 78)
        XCTAssertEqual(result["weeklyResetTime"] as? String, "Resets Aug 31, 2026 9:01 AM")
        XCTAssertEqual(result["success"] as? Bool, true)
    }

    @MainActor
    func testCodexFixtureAssociatesEachResetWithItsLimit() async throws {
        let result = try await scrapeCodexFixture("""
        <div>
          <div>5 hour usage limit</div>
          <div>91% remaining</div>
          <div>Resets 2:30 PM</div>
        </div>
        <div>
          <div>Weekly usage limit</div>
          <div>22% remaining</div>
          <div>Resets August 31, 2026 at 9:01 AM</div>
        </div>
        """)

        XCTAssertEqual(result["percentage"] as? Int, 9)
        XCTAssertEqual(result["resetTime"] as? String, "Resets 2:30 PM")
        XCTAssertEqual(result["weeklyPercentage"] as? Int, 78)
        XCTAssertEqual(result["weeklyResetTime"] as? String, "Resets August 31, 2026 at 9:01 AM")
    }

    @MainActor
    func testCodexHundredPercentRemainingMeansZeroPercentUsed() async throws {
        let result = try await scrapeCodexFixture("""
        <div>
          <div>Weekly usage limit</div>
          <div>100% remaining</div>
          <div>Resets Sep 1, 2026 12:00 PM</div>
        </div>
        """)

        XCTAssertEqual(result["weeklyPercentage"] as? Int, 0)
        XCTAssertTrue(result["percentage"] is NSNull)
    }

    @MainActor
    func testCodexResetIgnoresExplanatoryResetCopy() async throws {
        let result = try await scrapeCodexFixture("""
        <div>
          <div>Weekly usage limit</div>
          <div>22% remaining</div>
          <div>Resets</div>
          <div>Use a reset to restore your weekly limit.</div>
          <div>Resets August 31, 2026 at 9:01 AM</div>
        </div>
        """)

        XCTAssertEqual(result["weeklyPercentage"] as? Int, 78)
        XCTAssertEqual(result["weeklyResetTime"] as? String, "Resets August 31, 2026 at 9:01 AM")
    }

    @MainActor
    func testCodexCountsEachUseResetButtonAsAnAvailableReset() async throws {
        let result = try await scrapeCodexFixture("""
        <div><span>Weekly limit</span><span>Resets in 6d 2h</span><span>22% left</span></div>
        <div>Usage limit resets</div>
        <div>Use a reset to restore your 5-hour limit, weekly limit, or both</div>
        <div>Full reset Expires Oct 22 at 5:12 PM EDT <button>Use reset</button></div>
        <div>Weekly reset Expires Oct 29 at 5:12 PM EDT <button>Use reset</button></div>
        """)

        XCTAssertEqual(result["availableResets"] as? Int, 2)
    }

    @MainActor
    func testCodexWaitsForResetButtonsThatRenderAfterTheLimitCards() async throws {
        let result = try await scrapeCodexFixture("""
        <div><span>Weekly limit</span><span>Resets in 6d 2h</span><span>22% left</span></div>
        <div id="resets">Usage limit resets</div>
        """, beforeScrape: """
        setTimeout(() => document.getElementById('resets').insertAdjacentHTML('beforeend',
            '<button>Use reset</button><button>Use reset</button>'), 1000)
        """)

        XCTAssertEqual(result["availableResets"] as? Int, 2)
    }

    @MainActor
    func testCodexResetsSectionWithoutButtonsMeansZeroAvailable() async throws {
        let result = try await scrapeCodexFixture("""
        <div><span>Weekly limit</span><span>Resets in 6d 2h</span><span>22% left</span></div>
        <div>Usage limit resets</div>
        <div>Use a reset to restore your 5-hour limit, weekly limit, or both</div>
        <script>const strings = { useReset: "Use reset" };</script>
        """)

        XCTAssertEqual(result["availableResets"] as? Int, 0)
    }

    @MainActor
    func testCodexWithoutResetsSectionLeavesAvailableResetsUnset() async throws {
        let result = try await scrapeCodexFixture("""
        <div><span>Weekly limit</span><span>Resets in 6d 2h</span><span>22% left</span></div>
        """)

        XCTAssertTrue(result["availableResets"] is NSNull)
    }

    @MainActor
    private func scrapeCodexFixture(_ body: String, beforeScrape: String = "") async throws -> [String: Any] {
        let webView = WKWebView()
        let navigationWaiter = NavigationWaiter()

        await withCheckedContinuation { continuation in
            navigationWaiter.didFinish = { continuation.resume() }
            webView.navigationDelegate = navigationWaiter
            webView.loadHTMLString("<html><body>\(body)</body></html>", baseURL: nil)
        }

        let value = try await webView.callAsyncJavaScript(
            beforeScrape + ";\n" + CodexScrapingScript.script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        return try XCTUnwrap(value as? [String: Any])
    }
}

private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    var didFinish: (() -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish?()
        didFinish = nil
    }
}
