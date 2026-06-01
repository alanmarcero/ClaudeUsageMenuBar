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
            XCTAssertFalse(provider.usageURL.absoluteString.isEmpty)
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
