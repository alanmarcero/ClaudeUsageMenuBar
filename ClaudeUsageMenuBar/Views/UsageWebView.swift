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

            Text("\(provider.displayName) Usage")
                .font(.headline)

            Spacer()

            Button("Done") { windowManager.closeUsageWindow(provider: provider) }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
}
