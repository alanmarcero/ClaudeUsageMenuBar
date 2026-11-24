import Foundation
import Combine

// Owns one UsageService per provider and re-emits each service's changes as its own,
// so an observer of the container (the menu bar label) re-renders whenever any
// provider updates.
@MainActor
final class UsageProviders: ObservableObject {
    let services: [UsageService]
    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []

    private static let selectionKey = "menuBarProviderID"
    private static let hiddenKey = "hiddenProviderIDs"
    private static let cursorMetricKey = "cursorMenuBarMetricID"

    // Cursor reports several metrics; the menu bar can show any one of them.
    // There is no Included option: that total is just the two pools combined,
    // so it gets no bar and no menu-bar slot of its own.
    static let cursorMetricOptions: [(id: String, label: String)] = [
        ("other", "Other Models"),
        ("cursor", "Cursor Models"),
        ("ondemand", "On-demand")
    ]

    private static let geminiMetricKey = "geminiMenuBarMetricID"

    // Gemini provides two quota groups in retrieveUserQuotaSummary:
    // Gemini Models (Session + Weekly) and Claude and GPT models (Session + Weekly).
    static let geminiMetricOptions: [(id: String, label: String)] = [
        ("session", "Session"),
        ("weekly", "Weekly"),
        ("claudeGPTSession", "Session (Claude / GPT)"),
        ("claudeGPTWeekly", "Weekly (Claude / GPT)")
    ]

    nonisolated static func geminiMetricOptions(for data: UsageData) -> [(id: String, label: String)] {
        let extraOptions = data.geminiExtraRows.map { (id: "extra:\($0.id)", label: $0.label) }
        return [
            ("session", "Session"),
            ("weekly", "Weekly")
        ] + extraOptions + [
            ("claudeGPTSession", "Session (Claude / GPT)"),
            ("claudeGPTWeekly", "Weekly (Claude / GPT)")
        ]
    }

    // Which provider's percentage is shown in the menu bar. Persisted so it sticks
    // across launches. The dropdown picker scales to however many providers exist.
    @Published var selectedMenuBarProviderID: String {
        didSet { defaults.set(selectedMenuBarProviderID, forKey: Self.selectionKey) }
    }

    // Providers the user hid from the menu (the "Platforms" toggles). A hidden
    // provider keeps its login and cached snapshot but leaves the popover, the
    // header chips, and the tooltip, and its service pauses refreshing until it
    // is shown again. At least one provider always stays visible.
    @Published private(set) var hiddenProviderIDs: Set<String>

    // Which Cursor metric the menu bar shows while Cursor is the selected
    // provider. Chosen from the Cursor section's Menu button; persisted.
    @Published private(set) var cursorMenuBarMetricID: String

    // Which Gemini weekly pool the menu bar shows while Gemini is the selected
    // provider. Chosen from the Gemini section's Menu bar row; persisted.
    @Published private(set) var geminiMenuBarMetricID: String

    init(providers: [UsageProvider] = UsageProvider.all, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        services = providers.map { UsageService(provider: $0) }

        let validIDs = Set(providers.map(\.id))
        let saved = defaults.string(forKey: Self.selectionKey)
        let validSaved = providers.first { $0.id == saved }?.id
        let initialSelection: String
        let rewriteSelection = saved == "grokbot" && providers.contains(where: { $0.id == UsageProvider.cursor.id })
        if rewriteSelection {
            initialSelection = UsageProvider.cursor.id
        } else {
            initialSelection = validSaved ?? providers.first?.id ?? ""
        }

        let hadGrokBotHidden = defaults.stringArray(forKey: Self.hiddenKey)?.contains("grokbot") == true
        var hidden = Set(defaults.stringArray(forKey: Self.hiddenKey) ?? []).intersection(validIDs)
        hidden.remove("grokbot")
        if !providers.isEmpty && hidden.count >= providers.count {
            hidden.remove(providers[0].id)  // never launch with every provider hidden
        }

        let savedMetric = defaults.string(forKey: Self.cursorMetricKey)
        let migratedMetric: String? = switch savedMetric {
        case "included", "grokbot": "other"
        default: savedMetric
        }
        let initialCursorMetric = Self.cursorMetricOptions.contains { $0.id == migratedMetric }
            ? (migratedMetric ?? "other") : "other"

        let savedGeminiMetric = defaults.string(forKey: Self.geminiMetricKey)
        let migratedGeminiMetric: String? = switch savedGeminiMetric {
        case "flash", "carbon", "argon": "session"
        case "flashHydrogenNeon", "hydrogen", "neon": "weekly"
        case "opus": "claudeGPTSession"
        default: savedGeminiMetric
        }
        let initialGeminiMetric = Self.geminiMetricOptions.contains { $0.id == migratedGeminiMetric }
            ? (migratedGeminiMetric ?? "session") : "session"

        selectedMenuBarProviderID = initialSelection
        hiddenProviderIDs = hidden
        cursorMenuBarMetricID = initialCursorMetric
        geminiMenuBarMetricID = initialGeminiMetric

        if rewriteSelection {
            defaults.set(initialSelection, forKey: Self.selectionKey)
        }
        if hadGrokBotHidden {
            persistHidden()
        }
        if migratedMetric != savedMetric {
            defaults.set(initialCursorMetric, forKey: Self.cursorMetricKey)
        }

        services.forEach { $0.isRefreshPaused = hidden.contains($0.provider.id) }
        if hidden.contains(selectedMenuBarProviderID),
           let firstVisible = services.first(where: { !hidden.contains($0.provider.id) }) {
            selectedMenuBarProviderID = firstVisible.provider.id
            defaults.set(selectedMenuBarProviderID, forKey: Self.selectionKey)
        }

        services.forEach { service in
            service.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    var visibleServices: [UsageService] {
        services.filter { !hiddenProviderIDs.contains($0.provider.id) }
    }

    var selectorServices: [UsageService] {
        visibleServices
    }

    var sectionServices: [UsageService] {
        visibleServices
    }

    func isVisible(_ providerID: String) -> Bool {
        !hiddenProviderIDs.contains(providerID)
    }

    func setProviderVisible(_ visible: Bool, providerID: String) {
        guard let service = services.first(where: { $0.provider.id == providerID }) else { return }

        if visible {
            guard hiddenProviderIDs.contains(providerID) else { return }
            hiddenProviderIDs.remove(providerID)
            persistHidden()
            service.isRefreshPaused = false
            service.triggerRefresh()
            return
        }

        guard !hiddenProviderIDs.contains(providerID), visibleServices.count > 1 else { return }
        hiddenProviderIDs.insert(providerID)
        persistHidden()
        service.isRefreshPaused = true
        if selectedMenuBarProviderID == providerID {
            selectedMenuBarProviderID = visibleServices.first?.provider.id ?? providerID
        }
    }

    // Picking a Cursor metric also selects Cursor for the menu bar, so the
    // choice is visible right away instead of waiting for a chip tap.
    func setCursorMenuBarMetric(_ metricID: String) {
        guard Self.cursorMetricOptions.contains(where: { $0.id == metricID }) else { return }
        cursorMenuBarMetricID = metricID
        defaults.set(metricID, forKey: Self.cursorMetricKey)
        selectedMenuBarProviderID = UsageProvider.cursor.id
    }

    // Picking a Gemini pool also selects Gemini for the menu bar.
    func setGeminiMenuBarMetric(_ metricID: String) {
        let geminiData = services.first { $0.provider.id == UsageProvider.gemini.id }?.usageData ?? UsageData()
        let validOptions = Self.geminiMetricOptions(for: geminiData)
        guard validOptions.contains(where: { $0.id == metricID }) else { return }
        geminiMenuBarMetricID = metricID
        defaults.set(metricID, forKey: Self.geminiMetricKey)
        selectedMenuBarProviderID = UsageProvider.gemini.id
    }

    // The string the menu bar (and the provider's header chip) shows. Cursor
    // and Gemini have a metric choice; Codex falls back to weekly when its
    // session card is absent; other providers use their headline %.
    func menuBarDisplay(for service: UsageService) -> String {
        switch service.provider.id {
        case UsageProvider.cursor.id:
            return cursorMenuBarDisplay(for: service.usageData)
        case UsageProvider.gemini.id:
            return Self.geminiMenuBarDisplay(for: service.usageData, metricID: geminiMenuBarMetricID)
        case UsageProvider.codex.id:
            let data = service.usageData
            guard let percentage = data.dailyPercentage ?? data.weeklyPercentage else { return "--" }
            return "\(percentage)%"
        default:
            return service.usageData.displayPercentage
        }
    }

    // Gemini's scoped pools land in the sonnet/design slots in priority order
    // (Argon first), but a missing Argon pool shifts Claude & GPT into the
    // first slot, so the pool is matched by its label rather than its slot.
    // Weekly usage is never displayed on the menu bar for Flash or Opus; they
    // always show their 5-hour session limits.
    nonisolated static func geminiMenuBarDisplay(for data: UsageData, metricID: String) -> String {
        switch metricID {
        case "session", "flash":
            if data.isSessionDisabled || data.isWeeklyLimitReached {
                return "100%"
            }
            guard let session = data.percentage else { return "--" }
            return "\(session)%"
        case "weekly", "flashHydrogenNeon":
            guard let weekly = data.weeklyPercentage else { return "--" }
            return "\(weekly)%"
        case "claudeGPTSession", "opus":
            if data.isDesignSessionUnavailable && (data.designDailyLabel != nil || data.designDailyPercentage != nil) {
                return "100%"
            }
            guard let session = data.designDailyPercentage else { return "--" }
            return "\(session)%"
        case "claudeGPTWeekly":
            guard let weekly = data.geminiClaudeGPTWeeklyPercentage else { return "--" }
            return "\(weekly)%"
        default:
            if metricID.hasPrefix("extra:") {
                let rowID = String(metricID.dropFirst("extra:".count))
                guard let row = data.geminiExtraRows.first(where: { $0.id == rowID }) else {
                    return data.dailyPercentage.map { "\($0)%" } ?? "--"
                }
                if row.isUnavailable {
                    return "100%"
                }
                return row.percentage.map { "\($0)%" } ?? "--"
            }
            guard let session = data.percentage else { return "--" }
            return "\(session)%"
        }
    }

    private func cursorMenuBarDisplay(for data: UsageData) -> String {
        switch cursorMenuBarMetricID {
        case "other":
            return data.weeklyPercentage.map { "\($0)%" } ?? "--"
        case "cursor":
            return data.sonnetWeeklyPercentage.map { "\($0)%" } ?? "--"
        case "ondemand":
            return data.onDemandUsedDollars.map(OnDemandUsage.format) ?? "--"
        default:
            return data.weeklyPercentage.map { "\($0)%" } ?? "--"
        }
    }

    private func persistHidden() {
        defaults.set(hiddenProviderIDs.sorted(), forKey: Self.hiddenKey)
    }

    var selectedService: UsageService? {
        visibleServices.first { $0.provider.id == selectedMenuBarProviderID } ?? visibleServices.first ?? services.first
    }

    func logout(providerID: String) {
        services.first { $0.provider.id == providerID }?.logout()
    }

    func logoutAll() {
        services.forEach { $0.logout() }
    }

    func refreshAll() {
        services.forEach { $0.resetCountdown() }
        visibleServices.forEach { $0.triggerRefresh() }
    }

    var isAnyRefreshing: Bool {
        visibleServices.contains { $0.isRefreshing }
    }

    var nextRefreshCountdown: Int {
        visibleServices.map { $0.countdown }.min() ?? 0
    }

    var combinedDebugInfo: String {
        services
            .map { "=== \($0.provider.displayName) ===\n\($0.debugInfo)" }
            .joined(separator: "\n\n")
    }
}