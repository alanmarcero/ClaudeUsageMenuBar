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
