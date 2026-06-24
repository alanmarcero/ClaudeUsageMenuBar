import SwiftUI
import ObjectiveC

struct MenuBarView: View {
    @EnvironmentObject var providers: UsageProviders
    @EnvironmentObject var updateService: UpdateService
    @EnvironmentObject var windowManager: WindowManager

    var body: some View {
        VStack(spacing: 0) {
            header
            menuBarPicker
            ForEach(providers.services, id: \.provider.id) { service in
                Divider().padding(.horizontal, 16)
                ProviderSection(service: service)
            }
            statusSection
            Divider().padding(.horizontal, 12)
            accountButtons
            Divider().padding(.horizontal, 12)
            globalButtons
        }
        .frame(width: 280)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Menu Bar Provider Picker

    // Selects which provider's percentage shows in the menu bar. A horizontal row of
    // glyph chips that scales to any number of providers.
    private var menuBarPicker: some View {
        HStack(spacing: 6) {
            Text("Menu bar")
                .font(.caption)
                .foregroundColor(.secondary)
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
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Usage")
                .font(.headline)
                .fontWeight(.semibold)
            Text("v\(appVersion)")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 16, height: 16)
                .opacity(providers.isAnyRefreshing ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    // MARK: - Status Section

    private var statusSection: some View {
        HStack {
            Text("Refresh in \(providers.nextRefreshCountdown)s")
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Account Buttons (per provider)

    private var accountButtons: some View {
        VStack(spacing: 4) {
            ForEach(providers.services, id: \.provider.id) { service in
                ActionButton(label: "Open \(service.provider.displayName) / Login", systemImage: "safari") {
                    windowManager.openUsageWindow(provider: service.provider, service: service)
                }
                ActionButton(
                    label: service.usageData.isLoggedIn ? "Log Out of \(service.provider.displayName)" : "Log In to \(service.provider.displayName)",
                    systemImage: service.usageData.isLoggedIn ? "rectangle.portrait.and.arrow.right" : "person.crop.circle"
                ) {
                    guard service.usageData.isLoggedIn else {
                        windowManager.openUsageWindow(provider: service.provider, service: service)
                        return
                    }
                    service.logout()
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Global Buttons

    private var globalButtons: some View {
        VStack(spacing: 4) {
            ActionButton(label: "Refresh All Now", systemImage: "arrow.clockwise", isLoading: providers.isAnyRefreshing, disabled: providers.isAnyRefreshing) {
                providers.refreshAll()
            }

            ActionButton(label: "Show Debug Info", systemImage: "ladybug") {
                DebugWindow.show(text: providers.combinedDebugInfo)
            }

            ActionButton(label: "Check for Updates...", systemImage: "arrow.down.circle", disabled: !updateService.canCheckForUpdates) {
                updateService.checkForUpdates()
            }

            ActionButton(label: "Clear Cache", systemImage: "trash") {
                providers.services.forEach { $0.clearCache() }
            }

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

            ActionButton(label: "Quit", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Provider Section

struct ProviderSection: View {
    @ObservedObject var service: UsageService

    var body: some View {
        VStack(spacing: 0) {
            providerHeader
            if let email = service.usageData.email {
                LabeledRow(label: "Email", value: email)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }

            usageRow("Daily", service.usageData.percentage, service.dailyResetCountdown)
            usageRow("Weekly", service.usageData.weeklyPercentage, service.weeklyResetCountdown)
            if service.usageData.sonnetWeeklyPercentage != nil {
                usageRow("Weekly (Sonnet)", service.usageData.sonnetWeeklyPercentage, service.sonnetWeeklyResetCountdown)
            }
            if service.usageData.designWeeklyPercentage != nil {
                usageRow("Weekly (Design)", service.usageData.designWeeklyPercentage, service.designWeeklyResetCountdown)
            }

            if let error = service.usageData.errorMessage {
                HStack(alignment: .top) {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .lineLimit(3)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
            }
        }
        .padding(.bottom, 6)
    }

    private var providerHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: service.provider.menuGlyph)
            Text(service.provider.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
            if let updated = service.usageData.lastUpdated {
                Text(RelativeTime.string(from: updated))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private func usageRow(_ title: String, _ percentage: Int?, _ resetTime: String?) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if let pct = percentage, pct >= AppConfig.shared.redThreshold {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                        .help("Usage is high")
                }
                Text(percentage.map { "\($0)%" } ?? "--")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(percentage != nil ? AppConfig.shared.colorForPercentage(percentage) : .secondary)
            }

            if let pct = percentage {
                UsageProgressBar(percentage: pct, colors: AppConfig.shared.gradientColors(for: pct))
            }

            if let reset = resetTime {
                LabeledRow(label: "Resets in", value: reset)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Reusable Components

struct LabeledRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text("\(label):")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
        }
    }
}

struct ActionButton: View {
    let label: String
    var systemImage: String? = nil
    var isLoading: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 16, alignment: .center)
                }
                Text(label)
                    .font(.subheadline)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.4)
                        .frame(width: 12, height: 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(isHovered && !disabled ? Color.primary.opacity(0.1) : Color.clear)
            .cornerRadius(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
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
