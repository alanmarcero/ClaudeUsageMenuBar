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
    static let cursorMetricOptions: [(id: String, label: String)] = [
        ("included", "Included"),
        ("other", "Other Models"),
        ("cursor", "Cursor Models"),
        ("ondemand", "On-demand"),
        ("grokbot", "Grok Bot")
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

        let savedMetric = defaults.string(forKey: Self.cursorMetricKey)
        cursorMenuBarMetricID = Self.cursorMetricOptions.contains { $0.id == savedMetric }
            ? (savedMetric ?? "included") : "included"

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
            cursorMenuBarMetricID = "included"
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

    // The string the menu bar (and the provider's header chip) shows. Only
    // Cursor has a metric choice; every other provider uses its headline %.
    func menuBarDisplay(for service: UsageService) -> String {
        guard service.provider.id == UsageProvider.cursor.id else {
            return service.usageData.displayPercentage
        }
        let data = service.usageData
        switch cursorMenuBarMetricID {
        case "other":
            return data.weeklyPercentage.map { "\($0)%" } ?? "--"
        case "cursor":
            return data.sonnetWeeklyPercentage.map { "\($0)%" } ?? "--"
        case "ondemand":
            return data.onDemandUsedDollars.map(OnDemandUsage.format) ?? "--"
        case "grokbot":
            guard isVisible(UsageProvider.grokBot.id),
                  let grok = grokBotService?.usageData.percentage else { return data.displayPercentage }
            return "\(grok)%"
        default:
            return data.displayPercentage
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
