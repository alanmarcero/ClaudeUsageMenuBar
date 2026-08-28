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
            XCTAssertTrue(provider.usagePathFragment.hasPrefix("/"), "\(provider.id) fragment")
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
    private func scrapeCodexFixture(_ body: String) async throws -> [String: Any] {
        let webView = WKWebView()
        let navigationWaiter = NavigationWaiter()

        await withCheckedContinuation { continuation in
            navigationWaiter.didFinish = { continuation.resume() }
            webView.navigationDelegate = navigationWaiter
            webView.loadHTMLString("<html><body>\(body)</body></html>", baseURL: nil)
        }

        let value = try await webView.callAsyncJavaScript(
            CodexScrapingScript.script,
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
