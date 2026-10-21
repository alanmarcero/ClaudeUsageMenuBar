import Foundation
import WebKit

// WKWebView's default User-Agent omits the "Version/X Safari/Y" suffix that
// Cloudflare's bot detection requires. Without it, claude.ai's challenge page
// can loop indefinitely on the visible WebView after logout.
enum SafariUserAgent {
    static let applicationName = "Version/17.6 Safari/605.1.15"
}

enum ClaudeWebViewFactory {
    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
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

    init(usageService: UsageService, provider: UsageProvider = .claude) {
        self.usageService = usageService
        self.provider = provider
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }

        let urlString = url.absoluteString.lowercased()

        if urlString.contains(provider.usagePathFragment) {
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
