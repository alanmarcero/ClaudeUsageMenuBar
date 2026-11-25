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

struct SecurityCLIWebCryptoKeychainStore: WebCryptoKeychainStore {
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-a", account, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let encoded = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return Data(base64Encoded: encoded)
    }

    func writeKey(_ data: Data) -> Bool {
        // Use interactive stdin (`security -i`) so the key never appears in process arguments (`ps aux`).
        let command = "add-generic-password -U -s \(quoted(service)) -a \(quoted(account)) -w \(quoted(data.base64EncodedString()))\n"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["-i"]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        input.fileHandleForWriting.write(Data(command.utf8))
        input.fileHandleForWriting.closeFile()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private func quoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

// Supplies WebKit's persistent IndexedDB WebCrypto wrapping key from a dedicated Keychain item
// managed via `/usr/bin/security` instead of plaintext UserDefaults or a CDHash-locked login
// keychain ACL that prompts after every ad-hoc rebuild.
final class WebCryptoMasterKeyDelegate: NSObject {
    static let shared = WebCryptoMasterKeyDelegate()
    static let legacyDefaultsKey = "webKitWebCryptoMasterKey"
    static let keyByteCount = 32

    private let lock = NSLock()
    private let defaults: UserDefaults
    private let keychain: WebCryptoKeychainStore
    private var cachedKey: Data?

    init(
        defaults: UserDefaults = .standard,
        keychain: WebCryptoKeychainStore = SecurityCLIWebCryptoKeychainStore()
    ) {
        self.defaults = defaults
        self.keychain = keychain
        super.init()
    }

    func masterKeyData() -> Data {
        lock.lock()
        defer { lock.unlock() }

        if let cachedKey, cachedKey.count == Self.keyByteCount {
            return cachedKey
        }

        if let keychainKey = keychain.readKey(), keychainKey.count == Self.keyByteCount {
            defaults.removeObject(forKey: Self.legacyDefaultsKey)
            cachedKey = keychainKey
            return keychainKey
        }

        if let legacyKey = defaults.data(forKey: Self.legacyDefaultsKey), legacyKey.count == Self.keyByteCount {
            if keychain.writeKey(legacyKey) {
                defaults.removeObject(forKey: Self.legacyDefaultsKey)
            }
            cachedKey = legacyKey
            return legacyKey
        }

        var bytes = [UInt8](repeating: 0, count: Self.keyByteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, Self.keyByteCount, &bytes)
        let generated = Data(bytes)
        _ = keychain.writeKey(generated)
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
            usageService.registerUsageBrowserWebView(webView)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            browserState?.update(from: webView)
            usageService.registerUsageBrowserWebView(webView)
        }
        guard let url = webView.url else { return }

        let urlString = url.absoluteString.lowercased()

        if provider.isUsagePage(urlString) {
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
