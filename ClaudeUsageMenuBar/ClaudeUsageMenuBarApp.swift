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
    private let providers = UsageProviders()
    private let updateService = UpdateService()
    private let windowManager = WindowManager()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItemController = StatusItemController(
            providers: providers,
            updateService: updateService,
            windowManager: windowManager
        )
    }
}

// Owns the menu bar status item and the popover that hosts the SwiftUI menu. The button's
// glyph and percentage track the selected provider; the popover lazily renders `MenuBarView`.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let providers: UsageProviders
    private var cancellable: AnyCancellable?

    init(providers: UsageProviders, updateService: UpdateService, windowManager: WindowManager) {
        self.providers = providers
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        popover.behavior = .transient
        let hosting = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(providers)
                .environmentObject(updateService)
                .environmentObject(windowManager)
        )
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover)
        }
        // Populate the icon + title BEFORE making the item visible. A zero-width (empty)
        // item gets parked off-screen at a sentinel position and never redraws when
        // content is added later, so it must have content first.
        updateButton()

        cancellable = providers.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateButton() }

        statusItem.isVisible = true
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let glyph = providers.selectedService?.provider.menuGlyph ?? "cpu"
        let percentage = providers.selectedService?.usageData.displayPercentage ?? "--"
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
