import SwiftUI
import AppKit
import Combine

// The app deliberately avoids SwiftUI's `MenuBarExtra`. On notched Macs with a full
// menu bar, the system destroys a `MenuBarExtra` status-item scene right after creating
// it, and because that scene is the app's only scene AppKit terminates the whole app
// (clean exit, no crash). An AppKit `NSStatusItem` instead just hides when there's no
// room, so the app keeps running. The invisible `Settings` scene exists only to give the
// SwiftUI `App` a valid scene; it never appears for this accessory app.
@main
struct ClaudeUsageMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItemController = StatusItemController()
    }
}

// Owns the menu bar status item and the popover that hosts the SwiftUI menu.
//
// CRITICAL ORDERING: the status item is created and made visible BEFORE the providers
// (and their background scraping web views) are initialized. If the heavy web-view
// machinery is created first — e.g. as a stored property that inits before this point —
// the status item arrives late and macOS denies it a menu-bar slot, parking it off-screen
// (and that bad placement then sticks). Create the item first; bring up providers after.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var providers: UsageProviders!
    private var updateService: UpdateService!
    private var windowManager: WindowManager!
    private var cancellable: AnyCancellable?
    private var lastButtonKey: String?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        // 1. Show the status item first, with a placeholder, so it claims its slot.
        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "Usage")
            button.title = " --"
            button.target = self
            button.action = #selector(togglePopover)
        }
        statusItem.isVisible = true

        // 2. Now bring up the providers (background web views) and wire up the menu.
        let providers = UsageProviders()
        self.providers = providers
        updateService = UpdateService()
        windowManager = WindowManager()

        popover.behavior = .transient
        let hosting = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(providers)
                .environmentObject(updateService)
                .environmentObject(windowManager)
        )
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        cancellable = providers.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateButton() }
        updateButton()
    }

    private func updateButton() {
        guard let providers, let button = statusItem.button else { return }
        button.toolTip = providers.services
            .map { UsageTooltip.line(provider: $0.provider.displayName, daily: $0.usageData.percentage, weekly: $0.usageData.weeklyPercentage) }
            .joined(separator: "\n")
        let glyph = providers.selectedService?.provider.menuGlyph ?? "cpu"
        let percentage = providers.selectedService?.usageData.displayPercentage ?? "--"
        // Skip redundant mutations (this fires ~once/sec via the countdown). Recreating
        // the NSImage and resetting the title only when something changed avoids needless
        // status-bar relayout.
        let key = "\(glyph)|\(percentage)"
        guard key != lastButtonKey else { return }
        lastButtonKey = key
        button.image = NSImage(systemSymbolName: glyph, accessibilityDescription: "Usage")
        button.title = " \(percentage)"
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // Accessory (LSUIElement) apps must activate before showing, or the popover
        // opens without the app becoming active and never renders on screen.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
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
