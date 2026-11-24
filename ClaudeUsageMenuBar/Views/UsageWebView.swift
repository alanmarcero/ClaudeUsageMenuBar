import SwiftUI

struct UsageWebView: View {
    let provider: UsageProvider
    @ObservedObject var service: UsageService
    @EnvironmentObject var windowManager: WindowManager
    @StateObject private var browserState = WebViewBrowserState()
    @State private var showingCertificatePopover = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            addressBar
            Divider()
            ProviderWebView(provider: provider, service: service, browserState: browserState)
        }
        .onAppear { service.setUsageBrowserOpen(true) }
        .onDisappear { service.setUsageBrowserOpen(false) }
    }

    private var toolbar: some View {
        HStack {
            HStack(spacing: 4) {
                Button(action: { browserState.webView?.goBack() }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .disabled(!browserState.canGoBack)
                .help("Back")

                Button(action: { browserState.webView?.goForward() }) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                .disabled(!browserState.canGoForward)
                .help("Forward")

                Button(action: {
                    browserState.webView?.reload()
                    service.triggerRefresh()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(service.isRefreshing)
                .help("Reload")
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: provider.menuGlyph)
                Text("\(provider.displayName) Usage")
                    .font(.headline)
                if service.isRefreshing {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                }
            }

            Spacer()

            Button("Done") { windowManager.closeUsageWindow(provider: provider) }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var addressBar: some View {
        HStack(spacing: 8) {
            Button(action: { showingCertificatePopover.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: browserState.isSecureHTTPS ? "lock.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(browserState.isSecureHTTPS ? .green : .orange)
                    if let subject = browserState.certificateSubject {
                        Text(subject)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("View TLS certificate details")
            .popover(isPresented: $showingCertificatePopover, arrowEdge: .bottom) {
                certificatePopover
            }

            Text(browserState.currentURL?.absoluteString ?? provider.usageURL.absoluteString)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.textBackgroundColor).opacity(0.6))
    }

    private var certificatePopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: browserState.isSecureHTTPS ? "lock.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(browserState.isSecureHTTPS ? .green : .orange)
                Text(browserState.isSecureHTTPS ? "Connection is secure (HTTPS)" : "Connection security warning")
                    .font(.headline)
            }

            Divider()

            if let host = browserState.currentURL?.host {
                labeledRow("Host", host)
            }
            if let subject = browserState.certificateSubject {
                labeledRow("Issued To", subject)
            }
            if let issuer = browserState.certificateIssuer {
                labeledRow("Issued By", issuer)
            }
            if browserState.certificateSubject == nil {
                Text("Certificate details will appear once TLS handshake completes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if browserState.serverTrust != nil {
                Divider()
                Button("View Full Certificate…") {
                    showingCertificatePopover = false
                    browserState.showSystemCertificatePanel()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
