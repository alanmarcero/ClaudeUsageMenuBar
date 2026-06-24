import SwiftUI

struct UsageWebView: View {
    let provider: UsageProvider
    @ObservedObject var service: UsageService
    @EnvironmentObject var windowManager: WindowManager

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ProviderWebView(provider: provider, service: service)
        }
    }

    private var toolbar: some View {
        HStack {
            Button(action: { service.triggerRefresh() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(service.isRefreshing)

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
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
}
