import Foundation
import Combine

// Owns one UsageService per provider and re-emits each service's changes as its own,
// so an observer of the container (the menu bar label) re-renders whenever any
// provider updates.
@MainActor
final class UsageProviders: ObservableObject {
    let services: [UsageService]
    private var cancellables: Set<AnyCancellable> = []

    init(providers: [UsageProvider] = UsageProvider.all) {
        services = providers.map { UsageService(provider: $0) }
        for service in services {
            service.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
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
