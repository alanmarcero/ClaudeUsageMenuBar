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
        ("ondemand", "On-demand"),
        ("grokbot", "Grok Bot")
    ]

    private static let geminiMetricKey = "geminiMenuBarMetricID"

    // Gemini reports separate pools for Argon, Claude & GPT (Opus), and Gemini
    // Flash; the menu bar can show any of them.
    static let geminiMetricOptions: [(id: String, label: String)] = [
        ("argon", "Argon"),
        ("opus", "Opus"),
        ("flash", "Flash")
    ]

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

        let saved = defaults.string(forKey: Self.selectionKey)
        let validSaved = providers.first { $0.id == saved }?.id
        selectedMenuBarProviderID = validSaved ?? providers.first?.id ?? ""

        let validIDs = Set(providers.map(\.id))
        var hidden = Set(defaults.stringArray(forKey: Self.hiddenKey) ?? []).intersection(validIDs)
        if !providers.isEmpty && hidden.count >= providers.count {
            hidden.remove(providers[0].id)  // never launch with every provider hidden
        }
        hiddenProviderIDs = hidden

        // A saved "included" pick predates its removal and lands here too.
        let savedMetric = defaults.string(forKey: Self.cursorMetricKey)
        cursorMenuBarMetricID = Self.cursorMetricOptions.contains { $0.id == savedMetric }
            ? (savedMetric ?? "other") : "other"

        let savedGeminiMetric = defaults.string(forKey: Self.geminiMetricKey)
        geminiMenuBarMetricID = Self.geminiMetricOptions.contains { $0.id == savedGeminiMetric }
            ? (savedGeminiMetric ?? "argon") : "argon"

        services.forEach { $0.isRefreshPaused = hidden.contains($0.provider.id) }
        // Grok Bot is combined into Cursor overall: it is no longer a top-level
        // menu-bar selection, so a saved Grok Bot selection becomes Cursor.
        if selectedMenuBarProviderID == UsageProvider.grokBot.id,
           providers.contains(where: { $0.id == UsageProvider.cursor.id }) {
            selectedMenuBarProviderID = UsageProvider.cursor.id
            defaults.set(selectedMenuBarProviderID, forKey: Self.selectionKey)
        }
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

    // Top-of-menu selector chips. Grok Bot has no chip: it is part of Cursor.
    var selectorServices: [UsageService] {
        visibleServices.filter { $0.provider.id != UsageProvider.grokBot.id }
    }

    // Sections the popover renders. While Cursor is visible, Grok Bot folds
    // into its section instead of getting its own; if Cursor is hidden, the
    // Grok Bot section stands alone so its data stays reachable.
    var sectionServices: [UsageService] {
        let grokFoldedIntoCursor = isVisible(UsageProvider.cursor.id)
        return visibleServices.filter {
            !($0.provider.id == UsageProvider.grokBot.id && grokFoldedIntoCursor)
        }
    }

    var grokBotService: UsageService? {
        services.first { $0.provider.id == UsageProvider.grokBot.id }
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
        if providerID == UsageProvider.grokBot.id && cursorMenuBarMetricID == "grokbot" {
            cursorMenuBarMetricID = "other"
            defaults.set(cursorMenuBarMetricID, forKey: Self.cursorMetricKey)
        }
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
        guard Self.geminiMetricOptions.contains(where: { $0.id == metricID }) else { return }
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
        case "flash":
            guard let session = data.percentage ?? data.dailyPercentage else { return "--" }
            return "\(session)%"
        case "opus":
            guard let session = data.designDailyPercentage else { return "--" }
            return "\(session)%"
        default: // "argon"
            let pools: [(label: String?, percentage: Int?)] = [
                (data.sonnetWeeklyLabel, data.sonnetWeeklyPercentage),
                (data.designWeeklyLabel, data.designWeeklyPercentage)
            ]
            let match = pools.first { $0.label?.lowercased().contains("argon") == true }
            guard let percentage = match?.percentage else {
                return data.dailyPercentage.map { "\($0)%" } ?? "--"
            }
            return "\(percentage)%"
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
        case "grokbot":
            guard isVisible(UsageProvider.grokBot.id),
                  let grok = grokBotService?.usageData.percentage else {
                return data.weeklyPercentage.map { "\($0)%" } ?? "--"
            }
            return "\(grok)%"
        default: // "other"
            return data.weeklyPercentage.map { "\($0)%" } ?? "--"
        }
    }

    private func persistHidden() {
        defaults.set(hiddenProviderIDs.sorted(), forKey: Self.hiddenKey)
    }

    var selectedService: UsageService? {
        visibleServices.first { $0.provider.id == selectedMenuBarProviderID } ?? visibleServices.first ?? services.first
    }

    func refreshAll() {
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
