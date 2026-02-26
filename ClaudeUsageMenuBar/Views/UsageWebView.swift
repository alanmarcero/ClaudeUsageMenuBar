import SwiftUI

struct UsageWebView: View {
    @EnvironmentObject var usageService: UsageService
    @EnvironmentObject var windowManager: WindowManager

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ClaudeWebView()
                .environmentObject(usageService)
        }
    }

    private var toolbar: some View {
        HStack {
            Button(action: { usageService.triggerRefresh() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(usageService.isRefreshing)

            Spacer()

            Text("Claude Usage")
                .font(.headline)

            Spacer()

            Button("Done") { windowManager.closeUsageWindow() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
}
