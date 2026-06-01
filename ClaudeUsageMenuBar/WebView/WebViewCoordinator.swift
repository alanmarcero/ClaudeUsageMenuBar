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
        guard navigationAction.request.url != nil else {
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

    func isAuthPage(_ urlString: String) -> Bool {
        ["/login", "/signin", "/oauth", "/callback", "/auth"].contains { urlString.contains($0) }
    }

    func isProviderMainPage(host: String, urlString: String) -> Bool {
        let isPrimary = host == provider.primaryHost || host == "www.\(provider.primaryHost)"
        return isPrimary && !isAuthPage(urlString)
    }
}
