import SwiftUI

@main
struct ClaudeUsageMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var usageService = UsageService()
    @StateObject private var windowManager = WindowManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(usageService)
                .environmentObject(windowManager)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu.fill")
                Text(usageService.displayText)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
class WindowManager: NSObject, ObservableObject, NSWindowDelegate {
    private var webViewWindow: NSWindow?

    func openUsageWindow(usageService: UsageService) {
        if let existingWindow = webViewWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = createWindow(usageService: usageService)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        webViewWindow = window
    }

    func closeUsageWindow() {
        webViewWindow?.close()
    }

    func windowWillClose(_ notification: Notification) {
        webViewWindow = nil
    }

    private func createWindow(usageService: UsageService) -> NSWindow {
        let contentView = UsageWebView()
            .environmentObject(usageService)
            .environmentObject(self)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Usage"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false

        return window
    }
}
