import Security
import SecurityInterface
import SwiftUI
import WebKit

@MainActor
final class WebViewBrowserState: ObservableObject {
    @Published var currentURL: URL?
    @Published var hasOnlySecureContent: Bool = false
    @Published var certificateSubject: String?
    @Published var certificateIssuer: String?
    @Published var serverTrust: SecTrust?
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    weak var webView: WKWebView?

    var isSecureHTTPS: Bool {
        currentURL?.scheme?.lowercased() == "https" && hasOnlySecureContent
    }

    func update(from webView: WKWebView) {
        self.webView = webView
        currentURL = webView.url
        hasOnlySecureContent = webView.hasOnlySecureContent
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward

        if let trust = webView.serverTrust,
           let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
           let leaf = chain.first {
            serverTrust = trust
            certificateSubject = SecCertificateCopySubjectSummary(leaf) as String?
            certificateIssuer = chain.count > 1 ? (SecCertificateCopySubjectSummary(chain[1]) as String?) : nil
        } else {
            serverTrust = webView.serverTrust
            certificateSubject = nil
            certificateIssuer = nil
        }
    }

    func showSystemCertificatePanel() {
        guard let trust = serverTrust else { return }
        let panel = SFCertificatePanel.shared()
        if let window = webView?.window ?? NSApp.keyWindow {
            panel?.beginSheet(for: window, modalDelegate: nil, didEnd: nil, contextInfo: nil, trust: trust, showGroup: true)
        } else {
            panel?.runModal(for: trust, showGroup: true)
        }
    }
}

struct ProviderWebView: NSViewRepresentable {
    let provider: UsageProvider
    let service: UsageService
    @ObservedObject var browserState: WebViewBrowserState

    func makeNSView(context: Context) -> WKWebView {
        let webView = ClaudeWebViewFactory.makeWebView(for: provider)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        browserState.webView = webView
        browserState.currentURL = provider.usageURL
        webView.load(URLRequest(url: provider.usageURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(usageService: service, provider: provider, browserState: browserState)
    }
}
