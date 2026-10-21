import SwiftUI
import ObjectiveC

struct MenuBarView: View {
    @EnvironmentObject var providers: UsageProviders
    @EnvironmentObject var updateService: UpdateService

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(providers.services, id: \.provider.id) { service in
                Divider().padding(.horizontal, 16)
                ProviderSection(service: service)
            }
            Divider()
            footer
        }
        .frame(width: 280)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    // The glyph chips select which provider's percentage shows in the menu bar.
    private var header: some View {
        HStack(spacing: 6) {
            Text("Usage")
                .font(.headline)
            Spacer()
            ForEach(providers.services, id: \.provider.id) { service in
                let isSelected = providers.selectedMenuBarProviderID == service.provider.id
                Button {
                    providers.selectedMenuBarProviderID = service.provider.id
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: service.provider.menuGlyph)
                        Text(service.usageData.displayPercentage)
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isSelected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                    )
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show \(service.provider.displayName) in the menu bar")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 4) {
            IconButton(systemImage: "arrow.clockwise", help: "Refresh all now") {
                providers.refreshAll()
            }
            .disabled(providers.isAnyRefreshing)
            Text(providers.isAnyRefreshing ? "Refreshing…" : "Refresh in \(providers.nextRefreshCountdown)s")
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
            Spacer()
            moreMenu
            IconButton(systemImage: "power", help: "Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var moreMenu: some View {
        Menu {
            Button("Settings…") { SettingsWindow.show() }
            Button("Check for Updates…") { updateService.checkForUpdates() }
                .disabled(!updateService.canCheckForUpdates)
            Divider()
            Button("Show Debug Info") { DebugWindow.show(text: providers.combinedDebugInfo) }
            Button("Clear Cache") { providers.services.forEach { $0.clearCache() } }
            Divider()
            Button("About \(appVersionLabel)") { AboutWindow.show() }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }

    private var appVersionLabel: String {
        "v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
    }
}

// MARK: - Provider Section

struct ProviderSection: View {
    @ObservedObject var service: UsageService
    @EnvironmentObject var windowManager: WindowManager

    var body: some View {
        VStack(spacing: 10) {
            providerHeader

            if service.provider.id != UsageProvider.codex.id || service.usageData.hasDailyLimit {
                usageRow("Daily", service.usageData.percentage, service.dailyResetCountdown)
            }
            usageRow("Weekly", service.usageData.weeklyPercentage, service.weeklyResetCountdown)
            if service.usageData.sonnetWeeklyPercentage != nil {
                usageRow("Weekly (\(service.usageData.sonnetWeeklyLabel ?? "Sonnet"))", service.usageData.sonnetWeeklyPercentage, service.sonnetWeeklyResetCountdown)
            }
            if service.usageData.designWeeklyPercentage != nil {
                usageRow("Weekly (\(service.usageData.designWeeklyLabel ?? "Design"))", service.usageData.designWeeklyPercentage, service.designWeeklyResetCountdown)
            }
            if let resets = service.usageData.availableResets {
                resetsRow(resets)
            }

            if let error = service.usageData.errorMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(error)
                        .lineLimit(3)
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundColor(.orange)
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func openUsageWindow() {
        windowManager.openUsageWindow(provider: service.provider, service: service)
    }

    private var providerHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: service.provider.menuGlyph)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(service.provider.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if let plan = service.usageData.planName {
                        Text(plan)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.08))
                            .cornerRadius(4)
                    }
                }
                if let email = service.usageData.email {
                    Text(email)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if let updated = service.usageData.lastUpdated {
                Text(RelativeTime.string(from: updated))
                    .font(.caption2)
                    .foregroundColor(RelativeTime.isStale(updated) ? .orange : .secondary)
            }
            IconButton(systemImage: "safari", help: "Open \(service.provider.displayName)") {
                // Claude Code's login can't sign in the embedded web view, so with it the
                // page opens in the default browser and there is no app login to manage.
                guard service.isUsingClaudeCodeLogin else {
                    openUsageWindow()
                    return
                }
                NSWorkspace.shared.open(service.provider.usageURL)
            }
            if !service.isUsingClaudeCodeLogin && service.usageData.isLoggedIn {
                IconButton(systemImage: "rectangle.portrait.and.arrow.right", help: "Log out of \(service.provider.displayName)") {
                    service.logout()
                }
            }
            if !service.isUsingClaudeCodeLogin && !service.usageData.isLoggedIn {
                IconButton(systemImage: "person.crop.circle", help: "Log in to \(service.provider.displayName)", action: openUsageWindow)
            }
        }
    }

    private func usageRow(_ title: String, _ percentage: Int?, _ resetTime: String?) -> some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.subheadline)
                if let reset = resetTime {
                    Text("resets in \(reset)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let pct = percentage, pct >= AppConfig.shared.redThreshold {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                        .help("Usage is high")
                }
                Text(percentage.map { "\($0)%" } ?? "--")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(percentage != nil ? AppConfig.shared.colorForPercentage(percentage) : .secondary)
            }

            if let pct = percentage {
                UsageProgressBar(percentage: pct, colors: AppConfig.shared.gradientColors(for: pct))
            }
        }
    }

    private func resetsRow(_ resets: Int) -> some View {
        HStack(spacing: 6) {
            Text("Resets")
                .font(.subheadline)
            Text("\(resets)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Spacer()
            if resets > 0 {
                Button("Open Reset UI", action: openUsageWindow)
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - Reusable Components

struct IconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 22, height: 22)
                .background(isHovered ? Color.primary.opacity(0.1) : Color.clear)
                .cornerRadius(5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct UsageProgressBar: View {
    let percentage: Int
    let colors: [Color]

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(NSColor.separatorColor).opacity(0.45))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    // Floor the fill width so very small percentages still show a visible nub.
                    .frame(width: max(8, geometry.size.width * CGFloat(percentage) / 100))
                    .animation(.easeOut(duration: 0.4), value: percentage)
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Debug Window

enum DebugWindow {
    static func show(text: String) {
        let displayText = text.isEmpty ? "No debug data available" : text

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Debug Info"
        window.center()
        window.isReleasedWhenClosed = false

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 50, width: 600, height: 450))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = displayText
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView

        let copyButton = NSButton(frame: NSRect(x: 10, y: 10, width: 120, height: 30))
        copyButton.title = "Copy to Clipboard"
        copyButton.bezelStyle = .rounded

        let helper = ClipboardHelper(text: displayText)
        copyButton.target = helper
        copyButton.action = #selector(ClipboardHelper.copyToClipboard)

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        contentView.addSubview(scrollView)
        contentView.addSubview(copyButton)

        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        objc_setAssociatedObject(NSApp!, "debugWindow", window, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(NSApp!, "clipboardHelper", helper, .OBJC_ASSOCIATION_RETAIN)
    }
}

class ClipboardHelper: NSObject {
    private let text: String

    init(text: String) {
        self.text = text
    }

    @objc func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Settings

// Lets the user tune the percentage thresholds that drive the green/orange/red
// coloring. Bound to AppConfig.shared, which persists changes on edit.
struct SettingsView: View {
    @ObservedObject private var config = AppConfig.shared

    var body: some View {
        Form {
            Section("Usage color thresholds") {
                Stepper(value: $config.yellowThreshold, in: 1...(config.redThreshold - 1)) {
                    HStack(spacing: 8) {
                        Circle().fill(.orange).frame(width: 10, height: 10)
                        Text("Orange at \(config.yellowThreshold)% and above")
                    }
                }
                Stepper(value: $config.redThreshold, in: (config.yellowThreshold + 1)...100) {
                    HStack(spacing: 8) {
                        Circle().fill(.red).frame(width: 10, height: 10)
                        Text("Red at \(config.redThreshold)% and above")
                    }
                }
                HStack(spacing: 8) {
                    Circle().fill(.green).frame(width: 10, height: 10)
                    Text("Below \(config.yellowThreshold)% shows green")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 220)
    }
}

// Hosts SettingsView in a standalone window (same proven pattern as DebugWindow), so
// it works for an accessory app that has no visible app menu.
enum SettingsWindow {
    static func show() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        objc_setAssociatedObject(NSApp!, "settingsWindow", window, .OBJC_ASSOCIATION_RETAIN)
    }
}

// MARK: - About

struct AboutView: View {
    private static let repositoryURL = URL(string: "https://github.com/alanmarcero/ClaudeUsageMenuBar")!

    private var versionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 72, height: 72)
                Image(systemName: "cpu.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundColor(.accentColor)
            }

            VStack(spacing: 4) {
                Text("Claude Usage Menu Bar")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(versionDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("A macOS menu bar app that shows your AI usage at a glance. Track Claude and OpenAI Codex limits, reset countdowns, plan details, and refresh status without leaving the menu bar.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Link(destination: Self.repositoryURL) {
                Label("View on GitHub", systemImage: "link")
            }

            Text("MIT License · macOS 13 or later")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(28)
        .frame(width: 410)
    }
}

@MainActor
enum AboutWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 410, height: 350),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Claude Usage Menu Bar"
        window.contentView = NSHostingView(rootView: AboutView())
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
