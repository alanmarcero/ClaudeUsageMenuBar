import Foundation
import Security
import WebKit

// WKWebView's default User-Agent omits the "Version/X Safari/Y" suffix that
// Cloudflare's bot detection requires. Without it, claude.ai's challenge page
// can loop indefinitely on the visible WebView after logout.
enum SafariUserAgent {
    static let applicationName = "Version/17.6 Safari/605.1.15"
}

// Supplies WebKit's persistent IndexedDB WebCrypto wrapping key from the app's own
// sandbox UserDefaults instead of macOS's legacy login keychain. Without this delegate,
// ad-hoc signed builds get a new CDHash on each rebuild and macOS prompts for
// "Claude Usage WebCrypto Master Key" every time the app is reinstalled.
final class WebCryptoMasterKeyDelegate: NSObject {
    static let shared = WebCryptoMasterKeyDelegate()
    static let defaultsKey = "webKitWebCryptoMasterKey"
    static let keyByteCount = 32

    private let lock = NSLock()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    func masterKeyData() -> Data {
        lock.lock()
        defer { lock.unlock() }
        if let existing = defaults.data(forKey: Self.defaultsKey), existing.count == Self.keyByteCount {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: Self.keyByteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, Self.keyByteCount, &bytes)
        let generated = Data(bytes)
        defaults.set(generated, forKey: Self.defaultsKey)
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

    static func makeConfiguration() -> WKWebViewConfiguration {
        let dataStore = WKWebsiteDataStore.default()
        configureDefaultDataStore(dataStore)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.applicationNameForUserAgent = SafariUserAgent.applicationName
        return configuration
    }

    static func makeWebView(frame: CGRect = .zero) -> WKWebView {
        WKWebView(frame: frame, configuration: makeConfiguration())
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

        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, opensInBrowser(url) {
            NSWorkspace.shared.open(url)
            return nil
        }
        webView.load(navigationAction.request)
        return nil
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Task { @MainActor in
            browserState?.update(from: webView)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            browserState?.update(from: webView)
        }
        guard let url = webView.url else { return }

        let urlString = url.absoluteString.lowercased()

        if provider.isUsagePage(urlString) {
            Task { @MainActor in
                usageService.triggerRefresh()
            }
        }
    }

    func isAllowedHost(_ host: String) -> Bool {
        provider.oauthHostSuffixes.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    // A page, popup or redirect to a web host outside the provider and SSO list opens
    // in the default browser. Other sites cannot show in the signed-in, provider-titled
    // window. Subframes, such as bot checks, still load.
    func opensInBrowser(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased()) && !isAllowedHost(url.host ?? "")
    }

    func isAuthPage(_ urlString: String) -> Bool {
        ["/login", "/signin", "/oauth", "/callback", "/auth"].contains { urlString.contains($0) }
    }

    func isProviderMainPage(host: String, urlString: String) -> Bool {
        let isPrimary = host == provider.primaryHost || host == "www.\(provider.primaryHost)"
        return isPrimary && !isAuthPage(urlString)
    }
}
