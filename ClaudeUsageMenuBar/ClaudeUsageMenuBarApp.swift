import SwiftUI

@main
struct ClaudeUsageMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var providers = UsageProviders()
    @StateObject private var updateService = UpdateService()
    @StateObject private var windowManager = WindowManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(providers)
                .environmentObject(updateService)
                .environmentObject(windowManager)
        } label: {
            MenuBarLabel(providers: providers)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var providers: UsageProviders

    var body: some View {
        HStack(spacing: 3) {
            if let service = providers.selectedService {
                Image(systemName: service.provider.menuGlyph)
                Text(service.usageData.displayPercentage)
                    .monospacedDigit()
            } else {
                Image(systemName: "cpu")
                Text("--")
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
class WindowManager: NSObject, ObservableObject, NSWindowDelegate {
    private var windows: [String: NSWindow] = [:]

    func openUsageWindow(provider: UsageProvider, service: UsageService) {
        if let existing = windows[provider.id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = createWindow(provider: provider, service: service)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        windows[provider.id] = window
    }

    func closeUsageWindow(provider: UsageProvider) {
        windows[provider.id]?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        windows = windows.filter { $0.value !== closing }
    }

    private func createWindow(provider: UsageProvider, service: UsageService) -> NSWindow {
        let contentView = UsageWebView(provider: provider, service: service)
            .environmentObject(self)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(provider.displayName) Usage"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false

        return window
    }
}
