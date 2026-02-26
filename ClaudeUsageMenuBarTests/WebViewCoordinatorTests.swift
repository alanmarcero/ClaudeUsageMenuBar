import XCTest
@testable import ClaudeUsageMenuBar

final class WebViewCoordinatorTests: XCTestCase {

    var coordinator: WebViewCoordinator!

    @MainActor
    override func setUp() {
        super.setUp()
        let usageService = UsageService()
        coordinator = WebViewCoordinator(usageService: usageService)
    }

    override func tearDown() {
        coordinator = nil
        super.tearDown()
    }

    // MARK: - isAllowedHost Tests

    func testIsAllowedHostClaudeAI() {
        XCTAssertTrue(coordinator.isAllowedHost("claude.ai"))
        XCTAssertTrue(coordinator.isAllowedHost("www.claude.ai"))
        XCTAssertTrue(coordinator.isAllowedHost("api.claude.ai"))
    }

    func testIsAllowedHostAnthropic() {
        XCTAssertTrue(coordinator.isAllowedHost("anthropic.com"))
        XCTAssertTrue(coordinator.isAllowedHost("www.anthropic.com"))
        XCTAssertTrue(coordinator.isAllowedHost("console.anthropic.com"))
    }

    func testIsAllowedHostGoogleOAuth() {
        XCTAssertTrue(coordinator.isAllowedHost("google.com"))
        XCTAssertTrue(coordinator.isAllowedHost("accounts.google.com"))
        XCTAssertTrue(coordinator.isAllowedHost("googleapis.com"))
        XCTAssertTrue(coordinator.isAllowedHost("gstatic.com"))
    }

    func testIsAllowedHostAppleOAuth() {
        XCTAssertTrue(coordinator.isAllowedHost("apple.com"))
        XCTAssertTrue(coordinator.isAllowedHost("appleid.apple.com"))
        XCTAssertTrue(coordinator.isAllowedHost("icloud.com"))
    }

    func testIsAllowedHostMicrosoftOAuth() {
        XCTAssertTrue(coordinator.isAllowedHost("microsoftonline.com"))
        XCTAssertTrue(coordinator.isAllowedHost("login.microsoftonline.com"))
        XCTAssertTrue(coordinator.isAllowedHost("microsoft.com"))
        XCTAssertTrue(coordinator.isAllowedHost("live.com"))
    }

    func testIsAllowedHostEnterpriseSSO() {
        XCTAssertTrue(coordinator.isAllowedHost("okta.com"))
        XCTAssertTrue(coordinator.isAllowedHost("mycompany.okta.com"))
        XCTAssertTrue(coordinator.isAllowedHost("auth0.com"))
        XCTAssertTrue(coordinator.isAllowedHost("clerk.dev"))
        XCTAssertTrue(coordinator.isAllowedHost("clerk.accounts.dev"))
    }

    func testIsAllowedHostRejectsUnknownDomains() {
        XCTAssertFalse(coordinator.isAllowedHost("example.com"))
        XCTAssertFalse(coordinator.isAllowedHost("malicious-site.com"))
        XCTAssertFalse(coordinator.isAllowedHost("fakeclaude.ai.evil.com"))
        XCTAssertFalse(coordinator.isAllowedHost("notclaude.ai"))
    }

    func testIsAllowedHostRejectsPartialMatches() {
        // Should not match if domain is just a suffix without proper boundary
        XCTAssertFalse(coordinator.isAllowedHost("notclaude.ai"))
        XCTAssertFalse(coordinator.isAllowedHost("evilclaude.ai"))
        XCTAssertFalse(coordinator.isAllowedHost("fakegoogle.com"))
    }

    // MARK: - isAuthPage Tests

    func testIsAuthPageLogin() {
        XCTAssertTrue(coordinator.isAuthPage("https://claude.ai/login"))
        XCTAssertTrue(coordinator.isAuthPage("https://claude.ai/login?redirect=/"))
        XCTAssertTrue(coordinator.isAuthPage("/login"))
    }

    func testIsAuthPageSignin() {
        XCTAssertTrue(coordinator.isAuthPage("https://claude.ai/signin"))
        XCTAssertTrue(coordinator.isAuthPage("/signin"))
    }

    func testIsAuthPageOAuth() {
        XCTAssertTrue(coordinator.isAuthPage("https://accounts.google.com/oauth"))
        XCTAssertTrue(coordinator.isAuthPage("/oauth/authorize"))
        XCTAssertTrue(coordinator.isAuthPage("https://claude.ai/oauth/callback"))
    }

    func testIsAuthPageCallback() {
        XCTAssertTrue(coordinator.isAuthPage("https://claude.ai/callback"))
        XCTAssertTrue(coordinator.isAuthPage("/callback?code=abc123"))
    }

    func testIsAuthPageAuth() {
        XCTAssertTrue(coordinator.isAuthPage("https://claude.ai/auth"))
        XCTAssertTrue(coordinator.isAuthPage("/auth/google"))
    }

    func testIsAuthPageReturnsFalseForNonAuthPages() {
        XCTAssertFalse(coordinator.isAuthPage("https://claude.ai/settings/usage"))
        XCTAssertFalse(coordinator.isAuthPage("https://claude.ai/chat"))
        XCTAssertFalse(coordinator.isAuthPage("https://claude.ai/"))
        XCTAssertFalse(coordinator.isAuthPage("/settings"))
    }

    // MARK: - isClaudeMainPage Tests

    func testIsClaudeMainPageTrue() {
        XCTAssertTrue(coordinator.isClaudeMainPage(host: "claude.ai", urlString: "https://claude.ai/"))
        XCTAssertTrue(coordinator.isClaudeMainPage(host: "claude.ai", urlString: "https://claude.ai/chat"))
        XCTAssertTrue(coordinator.isClaudeMainPage(host: "www.claude.ai", urlString: "https://www.claude.ai/"))
        XCTAssertTrue(coordinator.isClaudeMainPage(host: "claude.ai", urlString: "https://claude.ai/settings"))
    }

    func testIsClaudeMainPageFalseForAuthPages() {
        XCTAssertFalse(coordinator.isClaudeMainPage(host: "claude.ai", urlString: "https://claude.ai/login"))
        XCTAssertFalse(coordinator.isClaudeMainPage(host: "claude.ai", urlString: "https://claude.ai/signin"))
        XCTAssertFalse(coordinator.isClaudeMainPage(host: "claude.ai", urlString: "https://claude.ai/oauth"))
        XCTAssertFalse(coordinator.isClaudeMainPage(host: "claude.ai", urlString: "https://claude.ai/callback"))
    }

    func testIsClaudeMainPageFalseForOtherHosts() {
        XCTAssertFalse(coordinator.isClaudeMainPage(host: "google.com", urlString: "https://google.com/"))
        XCTAssertFalse(coordinator.isClaudeMainPage(host: "anthropic.com", urlString: "https://anthropic.com/"))
        XCTAssertFalse(coordinator.isClaudeMainPage(host: "api.claude.ai", urlString: "https://api.claude.ai/"))
    }
}
