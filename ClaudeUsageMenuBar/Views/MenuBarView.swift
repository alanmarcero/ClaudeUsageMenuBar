import SwiftUI
import ObjectiveC

struct MenuBarView: View {
    @EnvironmentObject var providers: UsageProviders
    @EnvironmentObject var updateService: UpdateService

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(providers.sectionServices, id: \.provider.id) { service in
                        Divider().padding(.horizontal, 16)
                        ProviderSection(service: service)
                    }
                }
            }
            .frame(maxHeight: 700)
            Divider()
            footer
        }
        .frame(width: 360)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    // The glyph chips select which provider's percentage shows in the menu bar.
    private var header: some View {
        HStack(spacing: 6) {
            Text(appVersionLabel)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize()
            Spacer()
            ForEach(providers.selectorServices, id: \.provider.id) { service in
                let isSelected = providers.selectedMenuBarProviderID == service.provider.id
                Button {
                    providers.selectedMenuBarProviderID = service.provider.id
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: service.provider.menuGlyph)
                        Text(providers.menuBarDisplay(for: service))
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .fixedSize()
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
            IconButton(systemImage: "arrow.clockwise", help: "Refresh all now") {
                providers.refreshAll()
            }
            .disabled(providers.isAnyRefreshing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 4) {
            Button(action: { ModelPriceCheatSheetWindow.show() }) {
                HStack(spacing: 4) {
                    Image(systemName: "dollarsign.circle")
                    Text("Model Prices")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open Model Price Cheat Sheet")

            Spacer()
            platformsMenu
            moreMenu
            IconButton(systemImage: "power", help: "Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func platformVisibilityBinding(for providerID: String) -> Binding<Bool> {
        Binding(
            get: { providers.isVisible(providerID) },
            set: { providers.setProviderVisible($0, providerID: providerID) }
        )
    }

    // Standalone dropdown next to the More menu: which platforms are shown.
    private var platformsMenu: some View {
        Menu {
            ForEach(providers.services, id: \.provider.id) { service in
                Toggle(service.provider.displayName, isOn: platformVisibilityBinding(for: service.provider.id))
                    .disabled(providers.isVisible(service.provider.id) && providers.visibleServices.count == 1)
            }
        } label: {
            HStack(spacing: 3) {
                Text("Platforms")
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose which platforms are shown")
    }

    private var moreMenu: some View {
        Menu {
            Button("Model Price Cheat Sheet…") { ModelPriceCheatSheetWindow.show() }
            Divider()
            Button("Settings…") { SettingsWindow.show() }
            Button("Check for Updates…") { updateService.checkForUpdates() }
                .disabled(!updateService.canCheckForUpdates)
            Divider()
            Button("Show Debug Info") { DebugWindow.show(text: providers.combinedDebugInfo) }
            Button("Copy Debug Info") { ClipboardHelper(text: providers.combinedDebugInfo).copyToClipboard() }
            Button("Clear Cache") { providers.services.forEach { $0.clearCache() } }
            Divider()
            ForEach(providers.services, id: \.provider.id) { service in
                Button("Log Out of \(service.provider.displayName)") {
                    service.logout()
                }
                .disabled(!canLogOutFromMenu(service))
            }
            Button("Log Out of All Platforms") {
                providers.logoutAll()
            }
            .disabled(!providers.services.contains(where: canLogOutFromMenu))
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

    // Codex and Cursor can clear a web session any time. Claude and Gemini only
    // expose logout while CLI is not driving the session, or while usage is shown.
    private func canLogOutFromMenu(_ service: UsageService) -> Bool {
        guard service.provider.readsClaudeCodeLogin || service.provider.readsGeminiLogin else {
            return true
        }
        if service.isUsingClaudeCodeLogin {
            return service.usageData.isLoggedIn
        }
        return true
    }
}

// MARK: - Provider Section

struct ProviderSection: View {
    @ObservedObject var service: UsageService
    @EnvironmentObject var providers: UsageProviders
    @EnvironmentObject var windowManager: WindowManager

    var body: some View {
        VStack(spacing: 10) {
            providerHeader

            if service.provider.id == UsageProvider.cursor.id {
                cursorMenuMetricRow
            }
            if service.provider.id == UsageProvider.gemini.id {
                geminiMenuMetricRow
                geminiUsageRows(service: service)
            } else {
                // Cursor has no primary bar: its Included total is just the two
                // pools below combined, so only those pools get rows.
                if service.provider.id != UsageProvider.cursor.id,
                   service.provider.id != UsageProvider.codex.id || service.usageData.hasDailyLimit {
                    let isUnavailable = service.usageData.isPrimarySessionUnavailable(for: service.provider)
                    usageRow(
                        service.provider.primaryLabel,
                        service.usageData.percentage,
                        service.dailyResetCountdown,
                        isUnavailable: isUnavailable
                    )
                }
                if let secondaryLabel = service.provider.secondaryLabel {
                    usageRow(secondaryLabel, service.usageData.weeklyPercentage, service.weeklyResetCountdown)
                }
                if service.usageData.sonnetWeeklyPercentage != nil {
                    usageRow(service.usageData.sonnetWeeklyLabel ?? "Weekly (Sonnet)", service.usageData.sonnetWeeklyPercentage, service.sonnetWeeklyResetCountdown)
                }
                if service.usageData.designDailyPercentage != nil {
                    let isUnavailable = service.usageData.isDesignSessionUnavailable
                    usageRow(
                        service.usageData.designDailyLabel ?? "Session (Claude / GPT)",
                        service.usageData.designDailyPercentage,
                        service.designDailyResetCountdown,
                        isUnavailable: isUnavailable
                    )
                }
                if service.usageData.designWeeklyPercentage != nil {
                    usageRow(service.usageData.designWeeklyLabel ?? "Weekly (Design)", service.usageData.designWeeklyPercentage, service.designWeeklyResetCountdown)
                }
            }
            if let resets = service.usageData.availableResets {
                resetsRow(resets)
                ForEach(Array(service.usageData.resets.enumerated()), id: \.offset) { _, reset in
                    resetDetailRow(reset)
                }
            }
            if let used = service.usageData.creditsUsed, let limit = service.usageData.creditsLimit {
                creditsRow(used: used, limit: limit)
            }
            if service.usageData.onDemandUsedDollars != nil {
                onDemandRow
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

    // Row directly under the Cursor header, above its metrics: which Cursor
    // metric the menu bar shows.
    private var cursorMenuMetricRow: some View {
        menuMetricRow(
            options: UsageProviders.cursorMetricOptions,
            selectedID: providers.cursorMenuBarMetricID,
            fallbackLabel: "Other Models",
            help: "Choose which Cursor metric shows in the menu bar",
            select: providers.setCursorMenuBarMetric
        )
    }

    // Same control for Gemini: which pool or session shows in the menu bar.
    private var geminiMenuMetricRow: some View {
        menuMetricRow(
            options: UsageProviders.geminiMetricOptions(for: service.usageData),
            selectedID: providers.geminiMenuBarMetricID,
            fallbackLabel: "Session",
            help: "Choose which Gemini usage shows in the menu bar",
            select: providers.setGeminiMenuBarMetric
        )
    }

    @ViewBuilder
    private func geminiUsageRows(service: UsageService) -> some View {
        // 1. Gemini Models: Session (5-hour limit; shared across Neon, Carbon, Argon, Hydrogen, 3.8 Flash)
        if service.usageData.hasDailyLimit {
            usageRow(
                service.provider.primaryLabel,
                service.usageData.percentage,
                service.dailyResetCountdown,
                isUnavailable: service.usageData.isPrimarySessionUnavailable(for: service.provider),
                activeHelp: service.usageData.geminiSharedDescription
            )
        }

        // 2. Gemini Models: Weekly
        if let secondaryLabel = service.provider.secondaryLabel, service.usageData.weeklyPercentage != nil {
            usageRow(
                secondaryLabel,
                service.usageData.weeklyPercentage,
                service.weeklyResetCountdown,
                activeHelp: service.usageData.geminiSharedDescription
            )
        }

        // 3. Model-specific bars for any Gemini model that has its own standalone quota pool
        ForEach(service.usageData.geminiExtraRows) { row in
            usageRow(
                row.label,
                row.percentage,
                service.extraRowCountdown(for: row),
                isUnavailable: row.isUnavailable,
                activeHelp: row.helpText
            )
        }

        // 4. Claude and GPT models: Session (5-hour limit)
        if service.usageData.designDailyPercentage != nil || service.usageData.designDailyLabel != nil {
            usageRow(
                service.usageData.designDailyLabel ?? "Session (Claude / GPT)",
                service.usageData.designDailyPercentage,
                service.designDailyResetCountdown,
                isUnavailable: service.usageData.isDesignSessionUnavailable,
                activeHelp: service.usageData.geminiThirdPartyDescription
            )
        }

        // 5. Claude and GPT models: Weekly
        if let claudeGPTWeeklyPct = service.usageData.geminiClaudeGPTWeeklyPercentage {
            usageRow(
                service.usageData.geminiClaudeGPTWeeklyLabel,
                claudeGPTWeeklyPct,
                service.geminiClaudeGPTWeeklyResetCountdown,
                activeHelp: service.usageData.geminiThirdPartyDescription
            )
        }
    }

    // A labeled row with a bordered button showing the current pick, so it
    // reads as a control rather than another metric.
    private func menuMetricRow(
        options: [(id: String, label: String)],
        selectedID: String,
        fallbackLabel: String,
        help: String,
        select: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Text("Menu bar")
                .font(.subheadline)
            Spacer()
            Menu {
                ForEach(options, id: \.id) { option in
                    Button {
                        select(option.id)
                    } label: {
                        if selectedID == option.id {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(options.first { $0.id == selectedID }?.label ?? fallbackLabel)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.25), lineWidth: 1)
                )
                .cornerRadius(6)
                .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(help)
        }
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

    private func usageRow(
        _ title: String,
        _ percentage: Int?,
        _ resetTime: String?,
        isUnavailable: Bool = false,
        unavailableHelp: String? = nil,
        activeHelp: String? = nil
    ) -> some View {
        let titleParts = title.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let mainTitle = String(titleParts.first ?? Substring(title))
        let subtitle = titleParts.count > 1 ? String(titleParts[1]) : nil

        return VStack(spacing: 5) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(mainTitle)
                        .font(.subheadline)
                        .foregroundColor(isUnavailable ? .secondary : .primary)
                    if let reset = resetTime {
                        Text("resets in \(reset)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if !isUnavailable, let pct = percentage, pct >= AppConfig.shared.redThreshold {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                            .help("Usage is high")
                    }
                    let valueText = percentage.map { "\($0)%" } ?? (isUnavailable ? "Disabled" : "--")
                    Text(valueText)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(isUnavailable ? .secondary : (percentage != nil ? AppConfig.shared.colorForPercentage(percentage) : .secondary))
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(isUnavailable ? .secondary : .primary)
                }
            }

            if let pct = percentage {
                UsageProgressBar(
                    percentage: pct,
                    colors: isUnavailable
                        ? [Color.secondary.opacity(0.45), Color.secondary.opacity(0.3)]
                        : AppConfig.shared.gradientColors(for: pct)
                )
            }
        }
        .opacity(isUnavailable ? 0.55 : 1.0)
        .help(isUnavailable ? (unavailableHelp ?? "Unavailable: weekly limit reached") : (activeHelp ?? ""))
    }

    private func resetDetailRow(_ reset: UsageReset) -> some View {
        HStack(spacing: 6) {
            Text(reset.title ?? "Reset")
            Spacer()
            if let expires = reset.expires {
                Text("Expires \(expires)")
                    .foregroundColor(.secondary)
            }
        }
        .font(.caption)
    }

    // The user's own on-demand spend past the included pools.
    private var onDemandRow: some View {
        HStack(spacing: 6) {
            Text("On-demand")
                .font(.subheadline)
            Spacer()
            if let used = service.usageData.onDemandUsedDollars {
                Text(OnDemandUsage.format(used))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
    }

    private func creditsRow(used: Double, limit: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            usageRow("Credits", CreditUsage.percentage(used: used, limit: limit), nil)
            Text(CreditUsage.summary(used: used, limit: limit))
            Text(CreditUsage.estimatedSpend(used: used))
                .foregroundColor(.secondary)
        }
        .font(.caption)
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

            Text("A macOS menu bar app that shows your Claude, OpenAI Codex, Cursor, and Gemini usage limits, reset countdowns and plan.")
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

// MARK: - Model Price Cheat Sheet

struct ModelPriceEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let platformId: String
    let platformName: String
    let platformGlyph: String
    let inputPrice: Double
    let outputPrice: Double
    let note: String?

    init(
        id: String? = nil,
        name: String,
        platformId: String,
        platformName: String,
        platformGlyph: String,
        inputPrice: Double,
        outputPrice: Double,
        note: String? = nil
    ) {
        self.id = id ?? "\(platformId)-\(name)"
        self.name = name
        self.platformId = platformId
        self.platformName = platformName
        self.platformGlyph = platformGlyph
        self.inputPrice = inputPrice
        self.outputPrice = outputPrice
        self.note = note
    }

    var isLegacy: Bool {
        note?.hasPrefix("Legacy") == true
    }
}

enum ModelPriceSortColumn: String, CaseIterable, Equatable {
    case name
    case inputPrice
    case outputPrice
}

enum ModelPriceCatalog {
    static let platformFilters: [(id: String, label: String)] = [
        ("all", "All"),
        ("claude", "Claude"),
        ("codex", "Codex"),
        ("cursor", "Cursor"),
        ("gemini", "Gemini")
    ]

    static let entries: [ModelPriceEntry] = [
        // MARK: - Claude (Anthropic)
        ModelPriceEntry(name: "Claude Fable 5.2", platformId: "claude", platformName: "Claude", platformGlyph: "cpu.fill", inputPrice: 8.00, outputPrice: 40.00, note: "Frontier model for demanding reasoning and long-horizon work"),
        ModelPriceEntry(name: "Claude Fable 5.1", platformId: "claude", platformName: "Claude", platformGlyph: "cpu.fill", inputPrice: 10.00, outputPrice: 50.00, note: "Previous generation frontier model"),
        ModelPriceEntry(name: "Claude Fable 5", platformId: "claude", platformName: "Claude", platformGlyph: "cpu.fill", inputPrice: 10.00, outputPrice: 50.00, note: "Legacy frontier model"),
        ModelPriceEntry(name: "Claude Opus 5.5", platformId: "claude", platformName: "Claude", platformGlyph: "cpu.fill", inputPrice: 4.00, outputPrice: 20.00, note: "Latest Opus for agentic coding and knowledge work"),
        ModelPriceEntry(name: "Claude Opus 5", platformId: "claude", platformName: "Claude", platformGlyph: "cpu.fill", inputPrice: 5.00, outputPrice: 25.00, note: "Previous generation Opus for coding and knowledge work"),
        ModelPriceEntry(name: "Claude Opus 4.8", platformId: "claude", platformName: "Claude", platformGlyph: "cpu.fill", inputPrice: 5.00, outputPrice: 25.00, note: "Legacy Opus for complex work"),
        ModelPriceEntry(name: "Claude Opus 4.7", platformId: "claude", platformName: "Claude", platformGlyph: "cpu.fill", inputPrice: 5.00, outputPrice: 25.00, note: "Legacy Opus for complex work"),
        ModelPriceEntry(name: "Claude Opus 4.6", platformId: "claude", platformName: "Claude", platformGlyph: "cpu.fill", inputPrice: 5.00, outputPrice: 25.00, note: "Legacy Opus for complex work"),
        ModelPriceEntry(name: "Claude Opus 4.5", platformId: "claude", platformName: "Claude", platformGlyph: "cpu.fill", inputPrice: 5.00, outputPrice: 25.00, note: "Legacy Opus, retiring January 22"),
        ModelPriceEntry(name: "Claude Sonnet 5.5", platformId: "claude", platformName: "Claude", platformGlyph: "cpu.fill", inputPrice: 2.00, outputPrice: 10.00, note: "Latest Sonnet, best mix of speed and intelligence"),
        ModelPriceEntry(name: "Claude Sonnet 5", platformId: "claude", platformName: "Claude", platformGlyph: "cpu.fill", inputPrice: 2.00, outputPrice: 10.00, note: "Previous generation balanced model"),
        ModelPriceEntry(name: "Claude Sonnet 4.6", platformId: "claude", platformName: "Claude", platformGlyph: "cpu.fill", inputPrice: 3.00, outputPrice: 15.00, note: "Legacy balanced model"),
        ModelPriceEntry(name: "Claude Sonnet 4.5", platformId: "claude", platformName: "Claude", platformGlyph: "cpu.fill", inputPrice: 3.00, outputPrice: 15.00, note: "Legacy Sonnet, retiring November 30"),
        ModelPriceEntry(name: "Claude Haiku 5.5", platformId: "claude", platformName: "Claude", platformGlyph: "cpu.fill", inputPrice: 0.10, outputPrice: 0.50, note: "Fast model for high-volume tasks · ≤100K ($0.50/$2.50 >100K)"),
        ModelPriceEntry(name: "Claude Haiku 4.5", platformId: "claude", platformName: "Claude", platformGlyph: "cpu.fill", inputPrice: 1.00, outputPrice: 5.00, note: "Previous generation fast model"),

        // MARK: - Codex (OpenAI)
        ModelPriceEntry(name: "GPT-6.2-Sol", platformId: "codex", platformName: "Codex", platformGlyph: "chevron.left.forwardslash.chevron.right", inputPrice: 2.00, outputPrice: 10.00, note: "Fast, go-to model for coding and everyday work"),
        ModelPriceEntry(name: "GPT-6.2-Astra", platformId: "codex", platformName: "Codex", platformGlyph: "chevron.left.forwardslash.chevron.right", inputPrice: 8.00, outputPrice: 40.00, note: "Our most capable model for complex coding and professional work"),
        ModelPriceEntry(name: "GPT-6.1 Terra", platformId: "codex", platformName: "Codex", platformGlyph: "chevron.left.forwardslash.chevron.right", inputPrice: 1.00, outputPrice: 5.00, note: "Efficient model that excels at visual understanding and computer use"),
        ModelPriceEntry(name: "GPT-6.1-Sol", platformId: "codex", platformName: "Codex", platformGlyph: "chevron.left.forwardslash.chevron.right", inputPrice: 2.00, outputPrice: 10.00, note: "Previous generation model for coding and everyday work"),
        ModelPriceEntry(name: "GPT-6-Astra", platformId: "codex", platformName: "Codex", platformGlyph: "chevron.left.forwardslash.chevron.right", inputPrice: 10.00, outputPrice: 50.00, note: "Previous generation model for complex coding and professional work"),
        ModelPriceEntry(name: "GPT-6-Sol", platformId: "codex", platformName: "Codex", platformGlyph: "chevron.left.forwardslash.chevron.right", inputPrice: 2.00, outputPrice: 10.00, note: "Legacy model for coding and everyday work"),
        ModelPriceEntry(name: "GPT-6-Luna", platformId: "codex", platformName: "Codex", platformGlyph: "chevron.left.forwardslash.chevron.right", inputPrice: 0.10, outputPrice: 0.50, note: "Fast and affordable model for easier tasks"),
        ModelPriceEntry(name: "GPT-5.6-Sol", platformId: "codex", platformName: "Codex", platformGlyph: "chevron.left.forwardslash.chevron.right", inputPrice: 4.00, outputPrice: 20.00, note: "Legacy flagship for complex professional work"),
        ModelPriceEntry(name: "GPT-5.6-Terra", platformId: "codex", platformName: "Codex", platformGlyph: "chevron.left.forwardslash.chevron.right", inputPrice: 2.00, outputPrice: 12.00, note: "Legacy balanced model for agentic coding"),
        ModelPriceEntry(name: "GPT-5.6-Luna", platformId: "codex", platformName: "Codex", platformGlyph: "chevron.left.forwardslash.chevron.right", inputPrice: 0.20, outputPrice: 1.20, note: "Legacy fast model for simpler tasks"),

        // MARK: - Cursor
        ModelPriceEntry(name: "Composer 2.5", platformId: "cursor", platformName: "Cursor", platformGlyph: "cursorarrow.rays", inputPrice: 0.50, outputPrice: 2.50, note: "Cursor coding model for agent work"),
        ModelPriceEntry(name: "Composer 2.5 (Fast)", platformId: "cursor", platformName: "Cursor", platformGlyph: "cursorarrow.rays", inputPrice: 3.00, outputPrice: 15.00, note: "Faster Cursor coding model"),
        ModelPriceEntry(name: "Grok 4.7", platformId: "cursor", platformName: "Cursor", platformGlyph: "cursorarrow.rays", inputPrice: 2.00, outputPrice: 6.00, note: "xAI model for coding and general work"),
        ModelPriceEntry(name: "Grok 4.7 (Fast)", platformId: "cursor", platformName: "Cursor", platformGlyph: "cursorarrow.rays", inputPrice: 4.00, outputPrice: 12.00, note: "Faster xAI model"),
        ModelPriceEntry(name: "Grok 4.6", platformId: "cursor", platformName: "Cursor", platformGlyph: "cursorarrow.rays", inputPrice: 2.00, outputPrice: 6.00, note: "Previous generation xAI model"),
        ModelPriceEntry(name: "Grok 4.5", platformId: "cursor", platformName: "Cursor", platformGlyph: "cursorarrow.rays", inputPrice: 2.00, outputPrice: 6.00, note: "Legacy xAI model"),
        ModelPriceEntry(name: "Claude Fable 5.2", platformId: "cursor", platformName: "Cursor", platformGlyph: "cursorarrow.rays", inputPrice: 8.00, outputPrice: 40.00, note: "Frontier model for demanding reasoning and long-horizon work"),
        ModelPriceEntry(name: "Claude Opus 5.5", platformId: "cursor", platformName: "Cursor", platformGlyph: "cursorarrow.rays", inputPrice: 4.00, outputPrice: 20.00, note: "Latest Opus for agentic coding and knowledge work"),
        ModelPriceEntry(name: "Claude Sonnet 5.5", platformId: "cursor", platformName: "Cursor", platformGlyph: "cursorarrow.rays", inputPrice: 2.00, outputPrice: 10.00, note: "Latest Sonnet, best mix of speed and intelligence"),
        ModelPriceEntry(name: "Claude Haiku 5.5", platformId: "cursor", platformName: "Cursor", platformGlyph: "cursorarrow.rays", inputPrice: 0.10, outputPrice: 0.50, note: "Fast model for high-volume tasks · ≤100K ($0.50/$2.50 >100K)"),
        ModelPriceEntry(name: "GPT-5.6 Sol", platformId: "cursor", platformName: "Cursor", platformGlyph: "cursorarrow.rays", inputPrice: 4.00, outputPrice: 20.00, note: "Legacy flagship for complex professional work"),
        ModelPriceEntry(name: "GPT-5.6 Terra", platformId: "cursor", platformName: "Cursor", platformGlyph: "cursorarrow.rays", inputPrice: 2.00, outputPrice: 12.00, note: "Legacy balanced model for agentic coding"),
        ModelPriceEntry(name: "GPT-5.6 Luna", platformId: "cursor", platformName: "Cursor", platformGlyph: "cursorarrow.rays", inputPrice: 0.20, outputPrice: 1.20, note: "Legacy fast model for simpler tasks"),
        ModelPriceEntry(name: "Gemini 4 Neon", platformId: "cursor", platformName: "Cursor", platformGlyph: "cursorarrow.rays", inputPrice: 3.00, outputPrice: 15.00, note: "Frontier model for complex engineering and science"),
        ModelPriceEntry(name: "Gemini 4 Carbon", platformId: "cursor", platformName: "Cursor", platformGlyph: "cursorarrow.rays", inputPrice: 2.00, outputPrice: 10.00, note: "Strongest reasoning for long-horizon work · Intro ($4/$20 Dec 1)"),
        ModelPriceEntry(name: "Gemini 4 Argon", platformId: "cursor", platformName: "Cursor", platformGlyph: "cursorarrow.rays", inputPrice: 2.00, outputPrice: 10.00, note: "Efficient frontier reasoning · Intro ($4/$20 Dec 1)"),
        ModelPriceEntry(name: "Gemini 4 Hydrogen", platformId: "cursor", platformName: "Cursor", platformGlyph: "cursorarrow.rays", inputPrice: 1.50, outputPrice: 7.50, note: "Fast model for everyday coding and agents"),
        ModelPriceEntry(name: "Gemini 3.1 Pro", platformId: "cursor", platformName: "Cursor", platformGlyph: "cursorarrow.rays", inputPrice: 2.00, outputPrice: 12.00, note: "Legacy Pro · ≤200K ($4/$18 >200K)"),
        ModelPriceEntry(name: "Gemini 3.8 Flash", platformId: "cursor", platformName: "Cursor", platformGlyph: "cursorarrow.rays", inputPrice: 0.75, outputPrice: 3.75, note: "Previous generation Flash for coding and agents"),
        ModelPriceEntry(name: "Muse Wonder", platformId: "cursor", platformName: "Cursor", platformGlyph: "cursorarrow.rays", inputPrice: 4.00, outputPrice: 20.00, note: "Meta model"),

        // MARK: - Gemini (Google AI / Antigravity)
        ModelPriceEntry(name: "Gemini 4 Neon", platformId: "gemini", platformName: "Gemini", platformGlyph: "sparkle", inputPrice: 3.00, outputPrice: 15.00, note: "Frontier model for complex engineering and science · Antigravity"),
        ModelPriceEntry(name: "Gemini 4 Carbon", platformId: "gemini", platformName: "Gemini", platformGlyph: "sparkle", inputPrice: 2.00, outputPrice: 10.00, note: "Strongest reasoning for long-horizon work · Antigravity · $4/$20 Dec 1"),
        ModelPriceEntry(name: "Gemini 4 Argon", platformId: "gemini", platformName: "Gemini", platformGlyph: "sparkle", inputPrice: 2.00, outputPrice: 10.00, note: "Efficient frontier reasoning · Antigravity · $4/$20 Dec 1"),
        ModelPriceEntry(name: "Gemini 4 Hydrogen", platformId: "gemini", platformName: "Gemini", platformGlyph: "sparkle", inputPrice: 1.50, outputPrice: 7.50, note: "Fast model for everyday coding and agents · Antigravity"),
        ModelPriceEntry(name: "Gemini 3.8 Flash", platformId: "gemini", platformName: "Gemini", platformGlyph: "sparkle", inputPrice: 0.75, outputPrice: 3.75, note: "Previous generation Flash for coding and agents · Antigravity · $1.50/$7.50 Jan 1"),
        ModelPriceEntry(name: "Gemini 3.7 Flash", platformId: "gemini", platformName: "Gemini", platformGlyph: "sparkle", inputPrice: 0.75, outputPrice: 3.75, note: "Legacy Flash, routes to 3.8"),
        ModelPriceEntry(name: "Gemini 3.6 Flash", platformId: "gemini", platformName: "Gemini", platformGlyph: "sparkle", inputPrice: 0.75, outputPrice: 3.75, note: "Legacy Flash model"),
        ModelPriceEntry(name: "Gemini 3.5 Flash-Lite", platformId: "gemini", platformName: "Gemini", platformGlyph: "sparkle", inputPrice: 0.30, outputPrice: 2.50, note: "Fastest low-cost model for high-volume tasks"),
        ModelPriceEntry(name: "Gemini 3.1 Pro", platformId: "gemini", platformName: "Gemini", platformGlyph: "sparkle", inputPrice: 2.00, outputPrice: 12.00, note: "Legacy Pro · ≤200K ($4/$18 >200K)"),
        ModelPriceEntry(name: "Gemini 3.1 Flash-Lite", platformId: "gemini", platformName: "Gemini", platformGlyph: "sparkle", inputPrice: 0.25, outputPrice: 1.50, note: "Legacy Flash-Lite, retiring May 2027"),
        ModelPriceEntry(name: "Gemini 3 Flash", platformId: "gemini", platformName: "Gemini", platformGlyph: "sparkle", inputPrice: 0.50, outputPrice: 3.00, note: "Legacy Flash model"),
        ModelPriceEntry(name: "Gemini 2.5 Pro", platformId: "gemini", platformName: "Gemini", platformGlyph: "sparkle", inputPrice: 1.25, outputPrice: 10.00, note: "Legacy Pro, retiring December 1"),
        ModelPriceEntry(name: "Gemini 2.5 Flash", platformId: "gemini", platformName: "Gemini", platformGlyph: "sparkle", inputPrice: 0.30, outputPrice: 2.50, note: "Legacy Flash, retiring December 1"),
        ModelPriceEntry(name: "Gemini 2.5 Flash-Lite", platformId: "gemini", platformName: "Gemini", platformGlyph: "sparkle", inputPrice: 0.10, outputPrice: 0.40, note: "Legacy low-cost model"),
    ]

    static func formatPrice(_ price: Double) -> String {
        if price >= 1.0 || price.truncatingRemainder(dividingBy: 0.01) == 0 {
            return String(format: "$%.2f", price)
        }
        let str = String(format: "$%.4f", price)
        var trimmed = str
        while trimmed.hasSuffix("0") && trimmed.contains(".") && trimmed.components(separatedBy: ".")[1].count > 2 {
            trimmed.removeLast()
        }
        return trimmed
    }

    struct GroupedPlatform: Identifiable {
        var id: String { platformId }
        let platformId: String
        let platformName: String
        let platformGlyph: String
        let models: [ModelPriceEntry]
    }

    static func sortModels(_ models: [ModelPriceEntry], by column: ModelPriceSortColumn, ascending: Bool) -> [ModelPriceEntry] {
        models.sorted { lhs, rhs in
            switch column {
            case .name:
                let lName = lhs.name.lowercased()
                let rName = rhs.name.lowercased()
                if lName != rName {
                    return ascending ? lName < rName : lName > rName
                }
                return lhs.outputPrice > rhs.outputPrice
            case .inputPrice:
                if lhs.inputPrice != rhs.inputPrice {
                    return ascending ? lhs.inputPrice < rhs.inputPrice : lhs.inputPrice > rhs.inputPrice
                }
                return lhs.outputPrice > rhs.outputPrice
            case .outputPrice:
                if lhs.outputPrice != rhs.outputPrice {
                    return ascending ? lhs.outputPrice < rhs.outputPrice : lhs.outputPrice > rhs.outputPrice
                }
                return lhs.inputPrice > rhs.inputPrice
            }
        }
    }

    static func groupedByPlatform(
        filter: String = "",
        includeLegacy: Bool = true,
        sortForGroup: ((String) -> (column: ModelPriceSortColumn, ascending: Bool))? = nil
    ) -> [GroupedPlatform] {
        let platformsOrder = ["claude", "codex", "cursor", "gemini"]
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = entries.filter { entry in
            if !includeLegacy && entry.isLegacy { return false }
            if query.isEmpty { return true }
            return entry.name.lowercased().contains(query) ||
                entry.platformName.lowercased().contains(query) ||
                (entry.note?.lowercased().contains(query) ?? false)
        }

        return platformsOrder.compactMap { pid in
            let platformModels = filtered.filter { $0.platformId == pid }
            guard !platformModels.isEmpty else { return nil }
            let sort = sortForGroup?(pid) ?? (.outputPrice, true)
            let sorted = sortModels(platformModels, by: sort.column, ascending: sort.ascending)
            let first = platformModels[0]
            return GroupedPlatform(platformId: pid, platformName: first.platformName, platformGlyph: first.platformGlyph, models: sorted)
        }
    }

    static func groupedByPlatformSortedByOutputAsc(filter: String = "", includeLegacy: Bool = true) -> [GroupedPlatform] {
        groupedByPlatform(filter: filter, includeLegacy: includeLegacy, sortForGroup: { _ in (.outputPrice, true) })
    }

    static func isCursorNativeModel(_ entry: ModelPriceEntry) -> Bool {
        entry.platformId == "cursor" &&
            (entry.name.hasPrefix("Composer") || entry.name.hasPrefix("Grok"))
    }

    static func cursorPriceSubgroups(from models: [ModelPriceEntry]) -> [(title: String, models: [ModelPriceEntry])] {
        let cursorModels = models.filter { isCursorNativeModel($0) }
        let otherModels = models.filter { !isCursorNativeModel($0) }
        return [
            ("Cursor Models", cursorModels),
            ("Other Models", otherModels)
        ].filter { !$0.models.isEmpty }
    }
}

final class ModelPriceCheatSheetPreferences: ObservableObject {
    static let showLegacyKey = "modelPriceCheatSheetShowLegacy"

    @Published var showLegacy: Bool {
        didSet { defaults.set(showLegacy, forKey: Self.showLegacyKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showLegacy = defaults.object(forKey: Self.showLegacyKey) as? Bool ?? true
    }
}

struct ModelPriceCheatSheetView: View {
    @StateObject private var preferences = ModelPriceCheatSheetPreferences()
    @State private var searchText: String = ""
    @State private var selectedPlatform: String = "all"
    @State private var groupSorts: [String: (column: ModelPriceSortColumn, ascending: Bool)] = [:]

    private var platformFilters: [(id: String, label: String)] {
        ModelPriceCatalog.platformFilters
    }

    private func currentSort(for platformId: String) -> (column: ModelPriceSortColumn, ascending: Bool) {
        groupSorts[platformId] ?? (.outputPrice, true)
    }

    private func toggleSort(for platformId: String, column: ModelPriceSortColumn) {
        let current = currentSort(for: platformId)
        if current.column == column {
            groupSorts[platformId] = (column, !current.ascending)
        } else {
            let defaultAscending = (column == .name || column == .outputPrice || column == .inputPrice)
            groupSorts[platformId] = (column, defaultAscending)
        }
    }

    private var groups: [ModelPriceCatalog.GroupedPlatform] {
        let all = ModelPriceCatalog.groupedByPlatform(filter: searchText, includeLegacy: preferences.showLegacy) { pid in
            currentSort(for: pid)
        }
        if selectedPlatform == "all" {
            return all
        }
        return all.filter { $0.platformId == selectedPlatform }
    }

    private var totalModelCount: Int {
        groups.reduce(0) { $0 + $1.models.count }
    }

    @ViewBuilder
    private func modelPriceTable(platformId: String, platformName: String, models: [ModelPriceEntry]) -> some View {
        let sort = currentSort(for: platformId)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: { toggleSort(for: platformId, column: .name) }) {
                    HStack(spacing: 4) {
                        Text("MODEL")
                        if sort.column == .name {
                            Image(systemName: sort.ascending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(sort.column == .name ? .accentColor : .secondary)
                .help("Sort \(platformName) models by name (\(sort.column == .name && sort.ascending ? "Z-A" : "A-Z"))")

                Button(action: { toggleSort(for: platformId, column: .inputPrice) }) {
                    HStack(spacing: 4) {
                        if sort.column == .inputPrice {
                            Image(systemName: sort.ascending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        Text("INPUT / 1M")
                    }
                    .frame(width: 95, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(sort.column == .inputPrice ? .accentColor : .secondary)
                .help("Sort \(platformName) models by input price (\(sort.column == .inputPrice && !sort.ascending ? "lowest first" : "highest first"))")

                Button(action: { toggleSort(for: platformId, column: .outputPrice) }) {
                    HStack(spacing: 4) {
                        if sort.column == .outputPrice {
                            Image(systemName: sort.ascending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        Text("OUTPUT / 1M")
                    }
                    .frame(width: 105, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(sort.column == .outputPrice ? .accentColor : .secondary)
                .help("Sort \(platformName) models by output price (\(sort.column == .outputPrice && !sort.ascending ? "lowest first" : "highest first"))")
            }
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))

            Divider()

            ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .font(.system(size: 13, weight: .medium))
                        if let note = model.note, note != "Cursor model" {
                            Text(note)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.06))
                                .cornerRadius(4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(ModelPriceCatalog.formatPrice(model.inputPrice))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 95, alignment: .trailing)

                    Text(ModelPriceCatalog.formatPrice(model.outputPrice))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(width: 105, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(index % 2 == 1 ? Color.primary.opacity(0.02) : Color.clear)

                if index < models.count - 1 {
                    Divider()
                        .opacity(0.4)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Label("Model Price Cheat Sheet", systemImage: "dollarsign.circle.fill")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("Prices per 1M tokens")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(6)
                }

                HStack(spacing: 12) {
                    // Search bar
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search models or platforms…", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .cornerRadius(6)
                    .frame(maxWidth: 240)

                    // Platform Filter Chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(platformFilters, id: \.id) { filter in
                                let isSelected = selectedPlatform == filter.id
                                Button(action: { selectedPlatform = filter.id }) {
                                    Text(filter.label)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06))
                                        .foregroundColor(isSelected ? .accentColor : .primary)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                                        )
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button(action: { preferences.showLegacy.toggle() }) {
                        Text(preferences.showLegacy ? "Hide legacy" : "Show legacy")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(preferences.showLegacy ? Color.primary.opacity(0.06) : Color.accentColor.opacity(0.25))
                            .foregroundColor(preferences.showLegacy ? .primary : .accentColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(preferences.showLegacy ? Color.clear : Color.accentColor, lineWidth: 1)
                            )
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help(preferences.showLegacy ? "Hide models marked Legacy" : "Show models marked Legacy")
                }
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Models list grouped by platform
            if groups.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No models matching \"\(searchText)\"")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 18) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: group.platformGlyph)
                                        .font(.headline)
                                        .foregroundColor(.accentColor)
                                    Text(group.platformName)
                                        .font(.headline)
                                        .fontWeight(.bold)
                                    Text("\(group.models.count) models")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.primary.opacity(0.06))
                                        .cornerRadius(4)
                                    Spacer()
                                }
                                .padding(.horizontal, 4)

                                if group.platformId == "cursor" {
                                    ForEach(Array(ModelPriceCatalog.cursorPriceSubgroups(from: group.models).enumerated()), id: \.offset) { _, subgroup in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(subgroup.title)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.secondary)
                                                .padding(.horizontal, 4)
                                            modelPriceTable(
                                                platformId: group.platformId,
                                                platformName: group.platformName,
                                                models: subgroup.models
                                            )
                                        }
                                    }
                                } else {
                                    modelPriceTable(
                                        platformId: group.platformId,
                                        platformName: group.platformName,
                                        models: group.models
                                    )
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }

            Divider()

            // Footer info
            HStack {
                Text("\(totalModelCount) models across \(groups.count) platform\(groups.count == 1 ? "" : "s") · Click column titles to sort")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Done") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 540, minHeight: 450)
    }
}

@MainActor
enum ModelPriceCheatSheetWindow {
    private static var window: NSWindow?

    static func show() {
        if let existing = window, existing.isVisible || existing.isMiniaturized {
            if existing.isMiniaturized {
                existing.deminiaturize(nil)
            }
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Model Price Cheat Sheet"
        newWindow.minSize = NSSize(width: 520, height: 420)
        newWindow.contentView = NSHostingView(rootView: ModelPriceCheatSheetView())
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = newWindow
    }
}
