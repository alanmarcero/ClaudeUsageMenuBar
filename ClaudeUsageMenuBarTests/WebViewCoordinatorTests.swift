import XCTest
import WebKit
@testable import ClaudeUsageMenuBar

final class WebViewCoordinatorTests: XCTestCase {

    var coordinator: WebViewCoordinator!
    var codexCoordinator: WebViewCoordinator!
    var cursorCoordinator: WebViewCoordinator!

    @MainActor
    override func setUp() {
        super.setUp()
        let claudeService = UsageService(provider: .claude)
        coordinator = WebViewCoordinator(usageService: claudeService, provider: .claude)
        let codexService = UsageService(provider: .codex)
        codexCoordinator = WebViewCoordinator(usageService: codexService, provider: .codex)
        let cursorService = UsageService(provider: .cursor)
        cursorCoordinator = WebViewCoordinator(usageService: cursorService, provider: .cursor)
    }

    override func tearDown() {
        coordinator = nil
        codexCoordinator = nil
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

    // MARK: - opensInBrowser Tests

    func testOpensInBrowserForUnknownHost() {
        XCTAssertTrue(coordinator.opensInBrowser(URL(string: "https://example.com/")!))
        XCTAssertTrue(coordinator.opensInBrowser(URL(string: "http://fakeclaude.ai.evil.com/login")!))
    }

    func testOpensInBrowserKeepsAllowedHosts() {
        XCTAssertFalse(coordinator.opensInBrowser(URL(string: "https://claude.ai/settings/usage")!))
        XCTAssertFalse(coordinator.opensInBrowser(URL(string: "https://accounts.google.com/o/oauth2")!))
    }

    func testOpensInBrowserKeepsNonWebSchemes() {
        XCTAssertFalse(coordinator.opensInBrowser(URL(string: "about:blank")!))
    }

    func testCursorOpensInBrowserKeepsDashboardRedirectsInApp() {
        XCTAssertFalse(cursorCoordinator.opensInBrowser(URL(string: "https://workos.imgix.net/example")!))
        XCTAssertFalse(cursorCoordinator.opensInBrowser(URL(string: "https://js.stripe.com/v3/")!))
        XCTAssertTrue(cursorCoordinator.opensInBrowser(URL(string: "https://example.com/")!))
        XCTAssertTrue(cursorCoordinator.isAllowedHost("authenticator.cursor.sh"))
    }

    @MainActor
    func testBackgroundNavigationPolicyEnforcesHTTPSAndAllowlist() {
        let service = UsageService(provider: .claude)
        XCTAssertTrue(service.isAllowedBackgroundNavigation(URL(string: "https://claude.ai/settings/usage")!))
        XCTAssertTrue(service.isAllowedBackgroundNavigation(URL(string: "https://accounts.google.com/o/oauth2")!))
        XCTAssertFalse(service.isAllowedBackgroundNavigation(URL(string: "http://claude.ai/settings/usage")!))
        XCTAssertFalse(service.isAllowedBackgroundNavigation(URL(string: "https://evilclaude.ai/settings/usage")!))
        XCTAssertFalse(service.isAllowedBackgroundNavigation(URL(string: "https://example.com/")!))
    }

    @MainActor
    func testShouldRunResetsCheckRequiresPrimaryHTTPSHost() {
        let service = UsageService(provider: .claude)
        XCTAssertTrue(service.shouldRunResetsCheck(for: URL(string: "https://claude.ai/settings/usage")!))
        XCTAssertTrue(service.shouldRunResetsCheck(for: URL(string: "https://www.claude.ai/settings/usage")!))
        XCTAssertFalse(service.shouldRunResetsCheck(for: URL(string: "http://claude.ai/settings/usage")!))
        XCTAssertFalse(service.shouldRunResetsCheck(for: URL(string: "https://evilclaude.ai/settings/usage")!))
        XCTAssertFalse(service.shouldRunResetsCheck(for: URL(string: "https://evil.com/settings/usage")!))
        XCTAssertTrue(UsageProvider.claude.isPrimaryHost("claude.ai"))
        XCTAssertFalse(UsageProvider.claude.isPrimaryHost("evilclaude.ai"))
    }

    func testIsUsagePageRequiresHTTPSAndPrimaryHost() {
        XCTAssertTrue(UsageProvider.claude.isUsagePage("https://claude.ai/settings/usage"))
        XCTAssertTrue(UsageProvider.claude.isUsagePage("https://www.claude.ai/settings/usage"))
        XCTAssertFalse(UsageProvider.claude.isUsagePage("http://claude.ai/settings/usage"))
        XCTAssertFalse(UsageProvider.claude.isUsagePage("https://accounts.google.com/settings/usage"))
        XCTAssertFalse(UsageProvider.claude.isUsagePage("https://evil.okta.com/settings/usage"))
        XCTAssertFalse(UsageProvider.claude.isUsagePage("https://claude.ai/login?redirect=/settings/usage"))

        XCTAssertTrue(UsageProvider.cursor.canScrapeUsageFromURL(URL(string: "https://cursor.com/dashboard")!))
        XCTAssertFalse(UsageProvider.cursor.canScrapeUsageFromURL(URL(string: "http://cursor.com/dashboard")!))
    }

    func testVisibleNavigationRejectsHTTPOnAllowedHostsAndNonHTTPSchemes() {
        XCTAssertTrue(coordinator.isAllowedVisibleTopLevelURL(URL(string: "https://claude.ai/settings/usage")!))
        XCTAssertFalse(coordinator.isAllowedVisibleTopLevelURL(URL(string: "http://claude.ai/settings/usage")!))
        XCTAssertFalse(coordinator.isAllowedVisibleTopLevelURL(URL(string: "file:///etc/passwd")!))
        XCTAssertFalse(coordinator.isAllowedVisibleTopLevelURL(URL(string: "javascript:alert(1)")!))
        XCTAssertFalse(coordinator.isAllowedVisibleTopLevelURL(URL(string: "about:blank")!))

        XCTAssertTrue(coordinator.isAllowedVisibleNavigation(URL(string: "about:blank")!, isTopLevel: true))
        XCTAssertFalse(coordinator.isAllowedVisibleNavigation(URL(string: "http://claude.ai/login")!, isTopLevel: true))
        XCTAssertFalse(coordinator.isAllowedVisibleNavigation(URL(string: "file:///etc/passwd")!, isTopLevel: true))
        XCTAssertFalse(coordinator.isAllowedVisibleNavigation(URL(string: "http://challenges.cloudflare.com/")!, isTopLevel: false))
        XCTAssertTrue(coordinator.isAllowedVisibleNavigation(URL(string: "https://challenges.cloudflare.com/")!, isTopLevel: false))
        XCTAssertTrue(coordinator.isAllowedVisibleNavigation(URL(string: "about:srcdoc")!, isTopLevel: false))
    }

    @MainActor
    func testCreateWebViewWithRejectsNonHTTPSchemesAndHTTPAllowedHost() {
        let webView = ClaudeWebViewFactory.makeWebView(for: .claude)
        let config = webView.configuration

        final class StubNavigationAction: WKNavigationAction {
            private let _request: URLRequest
            init(url: URL) {
                self._request = URLRequest(url: url)
                super.init()
            }
            override var request: URLRequest { _request }
        }

        XCTAssertNil(coordinator.webView(webView, createWebViewWith: config, for: StubNavigationAction(url: URL(string: "file:///etc/passwd")!), windowFeatures: WKWindowFeatures()))
        XCTAssertNil(webView.url)
        XCTAssertNil(coordinator.webView(webView, createWebViewWith: config, for: StubNavigationAction(url: URL(string: "http://claude.ai/settings/usage")!), windowFeatures: WKWindowFeatures()))
        XCTAssertNil(webView.url)
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

    // MARK: - isProviderMainPage Tests

    func testIsProviderMainPageTrue() {
        XCTAssertTrue(coordinator.isProviderMainPage(host: "claude.ai", urlString: "https://claude.ai/"))
        XCTAssertTrue(coordinator.isProviderMainPage(host: "claude.ai", urlString: "https://claude.ai/chat"))
        XCTAssertTrue(coordinator.isProviderMainPage(host: "www.claude.ai", urlString: "https://www.claude.ai/"))
        XCTAssertTrue(coordinator.isProviderMainPage(host: "claude.ai", urlString: "https://claude.ai/settings"))
    }

    func testIsProviderMainPageFalseForAuthPages() {
        XCTAssertFalse(coordinator.isProviderMainPage(host: "claude.ai", urlString: "https://claude.ai/login"))
        XCTAssertFalse(coordinator.isProviderMainPage(host: "claude.ai", urlString: "https://claude.ai/signin"))
        XCTAssertFalse(coordinator.isProviderMainPage(host: "claude.ai", urlString: "https://claude.ai/oauth"))
        XCTAssertFalse(coordinator.isProviderMainPage(host: "claude.ai", urlString: "https://claude.ai/callback"))
    }

    func testIsProviderMainPageFalseForOtherHosts() {
        XCTAssertFalse(coordinator.isProviderMainPage(host: "google.com", urlString: "https://google.com/"))
        XCTAssertFalse(coordinator.isProviderMainPage(host: "anthropic.com", urlString: "https://anthropic.com/"))
        XCTAssertFalse(coordinator.isProviderMainPage(host: "api.claude.ai", urlString: "https://api.claude.ai/"))
    }

    // MARK: - Codex Provider Tests

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

    func testCodexProviderMainPageUsesProviderHost() {
        XCTAssertTrue(codexCoordinator.isProviderMainPage(host: "chatgpt.com", urlString: "https://chatgpt.com/"))
        XCTAssertFalse(codexCoordinator.isProviderMainPage(host: "claude.ai", urlString: "https://claude.ai/"))
    }

    // MARK: - ClaudeWebViewFactory Tests

    func testFactoryConfigurationSetsSafariUserAgent() {
        let configuration = ClaudeWebViewFactory.makeConfiguration()
        XCTAssertEqual(configuration.applicationNameForUserAgent, SafariUserAgent.applicationName)
    }

    func testSafariUserAgentContainsSafariSuffix() {
        // Cloudflare's bot mitigation requires both "Version/" and "Safari/" tokens.
        // If either is missing, claude.ai loops the challenge page after logout.
        XCTAssertTrue(SafariUserAgent.applicationName.contains("Version/"))
        XCTAssertTrue(SafariUserAgent.applicationName.contains("Safari/"))
    }

    @MainActor
    func testFactoryWebViewUsesSafariUserAgent() async throws {
        let webView = ClaudeWebViewFactory.makeWebView()
        let userAgent = try await webView.evaluateJavaScript("navigator.userAgent") as? String
        XCTAssertNotNil(userAgent)
        XCTAssertTrue(userAgent?.contains("Safari/") ?? false, "Expected UA to contain 'Safari/', got: \(userAgent ?? "nil")")
        XCTAssertTrue(userAgent?.contains("Version/") ?? false, "Expected UA to contain 'Version/', got: \(userAgent ?? "nil")")
    }

    func testWebCryptoMasterKeyDelegateGeneratesAndPersists32ByteKeyInKeychain() {
        let suiteName = "test-webcrypto-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        final class InMemoryKeychainStore: WebCryptoKeychainStore {
            var storedKey: Data?
            func readKey() -> Data? { storedKey }
            func writeKey(_ data: Data) -> Bool {
                storedKey = data
                return true
            }
        }

        let keychain = InMemoryKeychainStore()
        let delegate = WebCryptoMasterKeyDelegate(defaults: defaults, keychain: keychain)
        var callbackKey: Data?
        delegate.webCryptoMasterKey { data in
            callbackKey = data
        }

        XCTAssertEqual(callbackKey?.count, 32)
        XCTAssertEqual(keychain.storedKey, callbackKey)
        XCTAssertNil(defaults.data(forKey: WebCryptoMasterKeyDelegate.legacyDefaultsKey))
        XCTAssertEqual(delegate.masterKeyData(), callbackKey)

        let secondInstance = WebCryptoMasterKeyDelegate(defaults: defaults, keychain: keychain)
        XCTAssertEqual(secondInstance.masterKeyData(), callbackKey)
    }

    func testWebCryptoMasterKeyDelegateMigratesLegacyUserDefaultsKeyToKeychain() {
        let suiteName = "test-webcrypto-migrate-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        final class InMemoryKeychainStore: WebCryptoKeychainStore {
            var storedKey: Data?
            func readKey() -> Data? { storedKey }
            func writeKey(_ data: Data) -> Bool {
                storedKey = data
                return true
            }
        }

        let legacyKey = Data((0..<32).map { UInt8($0) })
        defaults.set(legacyKey, forKey: WebCryptoMasterKeyDelegate.legacyDefaultsKey)

        let keychain = InMemoryKeychainStore()
        let delegate = WebCryptoMasterKeyDelegate(defaults: defaults, keychain: keychain)

        XCTAssertEqual(delegate.masterKeyData(), legacyKey)
        XCTAssertEqual(keychain.storedKey, legacyKey)
        XCTAssertNil(defaults.data(forKey: WebCryptoMasterKeyDelegate.legacyDefaultsKey))
    }

    func testWebCryptoMasterKeyDelegateRejectsFailedRNGWithoutWritingAllZeroKey() {
        let suiteName = "test-webcrypto-rng-fail-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        final class SpyKeychainStore: WebCryptoKeychainStore {
            var writeCalls = 0
            func readKey() -> Data? { nil }
            func writeKey(_ data: Data) -> Bool {
                writeCalls += 1
                return true
            }
        }

        let keychain = SpyKeychainStore()
        let delegate = WebCryptoMasterKeyDelegate(
            defaults: defaults,
            keychain: keychain,
            generateRandomBytes: { _, _ in errSecParam }
        )

        var callbackKey: Data? = Data([1, 2, 3])
        delegate.webCryptoMasterKey { data in
            callbackKey = data
        }

        XCTAssertNil(callbackKey)
        XCTAssertNil(delegate.masterKeyData())
        XCTAssertEqual(keychain.writeCalls, 0)
    }

    func testSecItemWebCryptoKeychainStoreRoundTrip() {
        let service = "com.alanmarcero.claudeusagemenubar.webcrypto.test.\(UUID().uuidString)"
        let store = SecItemWebCryptoKeychainStore(service: service, account: "test-key")
        defer {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "test-key"
            ]
            SecItemDelete(query as CFDictionary)
        }

        let key = Data((0..<32).map { UInt8(($0 * 7 + 3) & 0xFF) })
        XCTAssertTrue(store.writeKey(key))
        XCTAssertEqual(store.readKey(), key)
    }

    @MainActor
    func testProvidersUseIsolatedWebKitDataStores() {
        if #available(macOS 14.0, *) {
            let claudeStore = ClaudeWebViewFactory.dataStore(for: .claude)
            let codexStore = ClaudeWebViewFactory.dataStore(for: .codex)
            let cursorStore = ClaudeWebViewFactory.dataStore(for: .cursor)
            let geminiStore = ClaudeWebViewFactory.dataStore(for: .gemini)

            XCTAssertNotEqual(claudeStore.identifier, codexStore.identifier)
            XCTAssertNotEqual(codexStore.identifier, cursorStore.identifier)
            XCTAssertNotEqual(cursorStore.identifier, geminiStore.identifier)
            XCTAssertEqual(claudeStore.identifier, ClaudeWebViewFactory.dataStore(for: .claude).identifier)

            let getter = NSSelectorFromString("_delegate")
            for store in [claudeStore, codexStore, cursorStore, geminiStore] {
                let attached = store.perform(getter)?.takeUnretainedValue() as AnyObject?
                XCTAssertTrue(attached === WebCryptoMasterKeyDelegate.shared)
            }
        }
    }

    @MainActor
    func testDefaultDataStoreAttachesWebCryptoMasterKeyDelegate() {
        let dataStore = WKWebsiteDataStore.default()
        ClaudeWebViewFactory.configureDefaultDataStore(dataStore)

        let getter = NSSelectorFromString("_delegate")
        XCTAssertTrue(dataStore.responds(to: getter))
        let attached = dataStore.perform(getter)?.takeUnretainedValue() as AnyObject?
        XCTAssertTrue(attached === WebCryptoMasterKeyDelegate.shared)
    }
}
