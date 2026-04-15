import SwiftUI
import ObjectiveC

struct MenuBarView: View {
    @EnvironmentObject var usageService: UsageService
    @EnvironmentObject var windowManager: WindowManager

    var body: some View {
        VStack(spacing: 0) {
            header
            accountInfo
            Divider().padding(.horizontal, 16)
            usageSection(title: "Daily", percentage: usageService.usageData.percentage, resetTime: usageService.dailyResetCountdown, color: dailyUsageColor)
            Divider().padding(.horizontal, 16)
            usageSection(title: "Weekly", percentage: usageService.usageData.weeklyPercentage, resetTime: usageService.weeklyResetCountdown, color: weeklyUsageColor)
            if usageService.usageData.sonnetWeeklyPercentage != nil {
                Divider().padding(.horizontal, 16)
                usageSection(title: "Weekly (Sonnet)", percentage: usageService.usageData.sonnetWeeklyPercentage, resetTime: usageService.sonnetWeeklyResetCountdown, color: sonnetWeeklyUsageColor)
            }
            statusSection
            Divider().padding(.horizontal, 12)
            actionButtons
        }
        .frame(width: 260)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Claude Usage")
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 16, height: 16)
                .opacity(usageService.isRefreshing ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Account Info

    private var accountInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledRow(label: "Email", value: usageService.usageData.email ?? "--")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Refresh in \(usageService.countdown)s")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if let error = usageService.usageData.errorMessage {
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
        .padding(.bottom, 8)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 4) {
            ActionButton(label: "Open Usage Page / Login") {
                windowManager.openUsageWindow(usageService: usageService)
            }

            ActionButton(label: "Refresh Now", isLoading: usageService.isRefreshing, disabled: usageService.isRefreshing) {
                usageService.triggerRefresh()
            }

            ActionButton(label: "Show Debug Info") {
                DebugWindow.show(text: usageService.debugInfo)
            }

            ActionButton(label: "Clear Cache") {
                usageService.clearCache()
            }

            ActionButton(label: "Log Out") {
                usageService.logout()
            }

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

            ActionButton(label: "Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Usage Section

    private func usageSection(title: String, percentage: Int?, resetTime: String?, color: Color) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(percentage.map { "\($0)%" } ?? "--")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(percentage != nil ? color : .secondary)
            }

            if let pct = percentage {
                UsageProgressBar(percentage: pct, colors: AppConfig.shared.gradientColors(for: pct))
            }

            if let reset = resetTime {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledRow(label: "Resets in", value: reset)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Colors

    private var dailyUsageColor: Color {
        AppConfig.shared.colorForPercentage(usageService.usageData.percentage)
    }

    private var weeklyUsageColor: Color {
        AppConfig.shared.colorForPercentage(usageService.usageData.weeklyPercentage)
    }

    private var sonnetWeeklyUsageColor: Color {
        AppConfig.shared.colorForPercentage(usageService.usageData.sonnetWeeklyPercentage)
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
    var isLoading: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
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
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(NSColor.separatorColor).opacity(0.3))
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: geometry.size.width * CGFloat(percentage) / 100)
            }
        }
        .frame(height: 6)
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
