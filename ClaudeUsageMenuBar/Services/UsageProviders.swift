import Foundation
import Combine

// Owns one UsageService per provider and re-emits each service's changes as its own,
// so an observer of the container (the menu bar label) re-renders whenever any
// provider updates.
@MainActor
final class UsageProviders: ObservableObject {
    let services: [UsageService]
    private var cancellables: Set<AnyCancellable> = []

    private static let selectionKey = "menuBarProviderID"

    // Which provider's percentage is shown in the menu bar. Persisted so it sticks
    // across launches. The dropdown picker scales to however many providers exist.
    @Published var selectedMenuBarProviderID: String {
        didSet { UserDefaults.standard.set(selectedMenuBarProviderID, forKey: Self.selectionKey) }
    }

    init(providers: [UsageProvider] = UsageProvider.all) {
        services = providers.map { UsageService(provider: $0) }

        let saved = UserDefaults.standard.string(forKey: Self.selectionKey)
        let validSaved = providers.first { $0.id == saved }?.id
        selectedMenuBarProviderID = validSaved ?? providers.first?.id ?? ""

        services.forEach { service in
            service.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    var selectedService: UsageService? {
        services.first { $0.provider.id == selectedMenuBarProviderID } ?? services.first
    }

    func refreshAll() {
        services.forEach { $0.triggerRefresh() }
    }

    var isAnyRefreshing: Bool {
        services.contains { $0.isRefreshing }
    }

    var nextRefreshCountdown: Int {
        services.map { $0.countdown }.min() ?? 0
    }

    var combinedDebugInfo: String {
        services
            .map { "=== \($0.provider.displayName) ===\n\($0.debugInfo)" }
            .joined(separator: "\n\n")
    }
}
