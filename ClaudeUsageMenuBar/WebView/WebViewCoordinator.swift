import Foundation
import WebKit

class WebViewCoordinator: NSObject, WKNavigationDelegate {

    private enum Constants {
        static let redirectDelay: TimeInterval = 0.5
    }

    private let usageService: UsageService

    private let allowedHostSuffixes = [
        "claude.ai",
        "anthropic.com",
        "google.com",
        "googleapis.com",
        "gstatic.com",
        "apple.com",
        "icloud.com",
        "microsoftonline.com",
        "microsoft.com",
        "live.com",
        "okta.com",
        "auth0.com",
        "clerk.dev",
        "clerk.accounts.dev"
    ]

    init(usageService: UsageService) {
        self.usageService = usageService
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url,
              let host = url.host?.lowercased() else {
            decisionHandler(.cancel)
            return
        }

        if isAllowedHost(host) {
            decisionHandler(.allow)
        } else {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url,
              let host = url.host?.lowercased() else { return }

        let urlString = url.absoluteString.lowercased()

        if urlString.contains("/settings/usage") {
            Task { @MainActor in
                usageService.triggerRefresh()
            }
            return
        }

        if isAuthPage(urlString) {
            Task { @MainActor in
                usageService.setLoggedOut()
            }
            return
        }

        if isClaudeMainPage(host: host, urlString: urlString) {
            redirectToUsagePage(webView)
        }
    }

    func isAllowedHost(_ host: String) -> Bool {
        allowedHostSuffixes.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    func isAuthPage(_ urlString: String) -> Bool {
        ["/login", "/signin", "/oauth", "/callback", "/auth"].contains { urlString.contains($0) }
    }

    func isClaudeMainPage(host: String, urlString: String) -> Bool {
        let isClaudeAI = host == "claude.ai" || host == "www.claude.ai"
        return isClaudeAI && !isAuthPage(urlString)
    }

    private func redirectToUsagePage(_ webView: WKWebView) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.redirectDelay) {
            if let usageURL = URL(string: "https://claude.ai/settings/usage") {
                webView.load(URLRequest(url: usageURL))
            }
        }
    }
}
