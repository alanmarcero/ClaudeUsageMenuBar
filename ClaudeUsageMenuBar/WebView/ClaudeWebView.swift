import SwiftUI
import WebKit

struct ProviderWebView: NSViewRepresentable {
    let provider: UsageProvider
    let service: UsageService

    func makeNSView(context: Context) -> WKWebView {
        let webView = ClaudeWebViewFactory.makeWebView()
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: provider.usageURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(usageService: service, provider: provider)
    }
}
