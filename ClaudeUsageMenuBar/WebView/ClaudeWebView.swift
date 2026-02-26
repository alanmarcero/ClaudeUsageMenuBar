import SwiftUI
import WebKit

struct ClaudeWebView: NSViewRepresentable {
    @EnvironmentObject var usageService: UsageService

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        if let url = URL(string: "https://claude.ai/settings/usage") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(usageService: usageService)
    }
}
