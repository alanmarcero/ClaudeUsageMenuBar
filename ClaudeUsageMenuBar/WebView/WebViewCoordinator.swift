import Foundation
import Security
import WebKit

// WKWebView's default User-Agent omits the "Version/X Safari/Y" suffix that
// Cloudflare's bot detection requires. Without it, claude.ai's challenge page
// can loop indefinitely on the visible WebView after logout.
enum SafariUserAgent {
    static let applicationName = "Version/17.6 Safari/605.1.15"
}

protocol WebCryptoKeychainStore {
    func readKey() -> Data?
    @discardableResult
    func writeKey(_ data: Data) -> Bool
}

struct SecItemWebCryptoKeychainStore: WebCryptoKeychainStore {
    let service: String
    let account: String

    init(
        service: String = "com.alanmarcero.claudeusagemenubar.webcrypto",
        account: String = "webcrypto-master-key"
    ) {
        self.service = service
        self.account = account
    }

    func readKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let rawData = item as? Data else { return nil }
        if rawData.count == WebCryptoMasterKeyDelegate.keyByteCount {
            return rawData
        }
        let encoded = String(decoding: rawData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decoded = Data(base64Encoded: encoded),
              decoded.count == WebCryptoMasterKeyDelegate.keyByteCount else {
            return nil
        }
        return decoded
    }

    func writeKey(_ data: Data) -> Bool {
        guard data.count == WebCryptoMasterKeyDelegate.keyByteCount else { return false }
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }
}

// Supplies WebKit's persistent IndexedDB WebCrypto wrapping key from a Keychain item
// owned by the app via Security.framework (never `/usr/bin/security`, which would add
// the CLI tool to the item's ACL).
final class WebCryptoMasterKeyDelegate: NSObject {
    typealias RandomBytesGenerator = (Int, UnsafeMutableRawPointer) -> OSStatus

    static let shared = WebCryptoMasterKeyDelegate()
    static let legacyDefaultsKey = "webKitWebCryptoMasterKey"
    static let aclMigratedDefaultsKey = "webKitWebCryptoKeychainACLMigrated"
    static let keyByteCount = 32

    private let lock = NSLock()
    private let defaults: UserDefaults
    private let keychain: WebCryptoKeychainStore
    private let generateRandomBytes: RandomBytesGenerator
    private var cachedKey: Data?

    init(
        defaults: UserDefaults = .standard,
        keychain: WebCryptoKeychainStore = SecItemWebCryptoKeychainStore(),
        generateRandomBytes: @escaping RandomBytesGenerator = { count, buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer)
        }
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.generateRandomBytes = generateRandomBytes
        super.init()
    }

    func masterKeyData() -> Data? {
        lock.lock()
        defer { lock.unlock() }

        if let cachedKey, cachedKey.count == Self.keyByteCount {
            return cachedKey
        }

        if let keychainKey = keychain.readKey(), keychainKey.count == Self.keyByteCount {
            defaults.removeObject(forKey: Self.legacyDefaultsKey)
            if !defaults.bool(forKey: Self.aclMigratedDefaultsKey), keychain.writeKey(keychainKey) {
                defaults.set(true, forKey: Self.aclMigratedDefaultsKey)
            }
            cachedKey = keychainKey
            return keychainKey
        }

        if let legacyKey = defaults.data(forKey: Self.legacyDefaultsKey), legacyKey.count == Self.keyByteCount {
            if keychain.writeKey(legacyKey) {
                defaults.removeObject(forKey: Self.legacyDefaultsKey)
                defaults.set(true, forKey: Self.aclMigratedDefaultsKey)
            }
            cachedKey = legacyKey
            return legacyKey
        }

        var bytes = [UInt8](repeating: 0, count: Self.keyByteCount)
        let rngStatus = generateRandomBytes(Self.keyByteCount, &bytes)
        guard rngStatus == errSecSuccess else { return nil }

        let generated = Data(bytes)
        guard keychain.writeKey(generated) else { return nil }
        defaults.set(true, forKey: Self.aclMigratedDefaultsKey)
        cachedKey = generated
        return generated
    }

    @objc(webCryptoMasterKey:)
    func webCryptoMasterKey(_ completionHandler: @escaping (Data?) -> Void) {
        completionHandler(masterKeyData())
    }
}

enum ClaudeWebViewFactory {
    static func configureDefaultDataStore(_ dataStore: WKWebsiteDataStore = .default()) {
        let setter = NSSelectorFromString("set_delegate:")
        guard dataStore.responds(to: setter) else { return }
        _ = dataStore.perform(setter, with: WebCryptoMasterKeyDelegate.shared)
    }

    static func dataStore(for provider: UsageProvider? = nil) -> WKWebsiteDataStore {
        guard #available(macOS 14.0, *), let provider else {
            let store = WKWebsiteDataStore.default()
            configureDefaultDataStore(store)
            return store
        }
        let store = WKWebsiteDataStore(forIdentifier: provider.dataStoreIdentifier)
        configureDefaultDataStore(store)
        return store
    }

    static func makeConfiguration(for provider: UsageProvider? = nil) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore(for: provider)
        configuration.applicationNameForUserAgent = SafariUserAgent.applicationName
        return configuration
    }

    static func makeWebView(frame: CGRect = .zero, for provider: UsageProvider? = nil) -> WKWebView {
        WKWebView(frame: frame, configuration: makeConfiguration(for: provider))
    }
}

class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {

    private let usageService: UsageService
    private let provider: UsageProvider
    private weak var browserState: WebViewBrowserState?

    init(usageService: UsageService, provider: UsageProvider = .claude, browserState: WebViewBrowserState? = nil) {
        self.usageService = usageService
        self.provider = provider
        self.browserState = browserState
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        let isTopLevel = navigationAction.targetFrame?.isMainFrame ?? true
        if isTopLevel && opensInBrowser(url) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        guard isAllowedVisibleNavigation(url, isTopLevel: isTopLevel) else {
            decisionHandler(.cancel)
            return
        }

        if navigationAction.targetFrame == nil {
            if isAllowedVisibleTopLevelURL(url) {
                webView.load(navigationAction.request)
            }
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        if opensInBrowser(url) {
            NSWorkspace.shared.open(url)
            return nil
        }
        if isAllowedVisibleTopLevelURL(url) {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Task { @MainActor in
            browserState?.update(from: webView)
            usageService.registerUsageBrowserWebView(webView)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            browserState?.update(from: webView)
            usageService.registerUsageBrowserWebView(webView)
        }
        guard let url = webView.url else { return }

        if provider.isUsagePage(url) {
            Task { @MainActor in
                usageService.scheduleVisibleBrowserScrapeAfterHydration(webView: webView)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            browserState?.update(from: webView)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            browserState?.update(from: webView)
        }
    }

    func isAllowedHost(_ host: String) -> Bool {
        provider.isAllowedHost(host)
    }

    func isAllowedVisibleTopLevelURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && isAllowedHost(url.host ?? "")
    }

    func isAllowedVisibleNavigation(_ url: URL, isTopLevel: Bool) -> Bool {
        if isTopLevel {
            return isAllowedVisibleTopLevelURL(url) || url.absoluteString.lowercased() == "about:blank"
        }
        return url.scheme?.lowercased() == "https"
            || ["about:blank", "about:srcdoc"].contains(url.absoluteString.lowercased())
    }

    // A page, popup or redirect to a web host outside the provider and SSO list opens
    // in the default browser. Other sites cannot show in the signed-in, provider-titled
    // window. Subframes, such as bot checks, still load.
    func opensInBrowser(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased()) else { return false }
        return !isAllowedHost(url.host ?? "")
    }

    func isAuthPage(_ urlString: String) -> Bool {
        ["/login", "/signin", "/oauth", "/callback", "/auth"].contains { urlString.contains($0) }
    }

    func isProviderMainPage(host: String, urlString: String) -> Bool {
        let isPrimary = host == provider.primaryHost || host == "www.\(provider.primaryHost)"
        return isPrimary && !isAuthPage(urlString)
    }
}
