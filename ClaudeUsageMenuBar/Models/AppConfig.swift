import Foundation
import SwiftUI

class AppConfig: ObservableObject {
    static let shared = AppConfig()

    @Published var yellowThreshold: Int = 55
    @Published var redThreshold: Int = 85

    private init() {
        loadFromUserDefaults()
    }

    func colorForPercentage(_ percentage: Int?) -> Color {
        guard let percentage = percentage else { return .secondary }
        if percentage >= redThreshold { return .red }
        if percentage >= yellowThreshold { return .orange }
        return .green
    }

    func gradientColors(for percentage: Int) -> [Color] {
        if percentage >= redThreshold { return [.red, .orange] }
        if percentage >= yellowThreshold { return [.orange, .yellow] }
        return [.green, .mint]
    }

    func saveToUserDefaults() {
        UserDefaults.standard.set(yellowThreshold, forKey: "yellowThreshold")
        UserDefaults.standard.set(redThreshold, forKey: "redThreshold")
    }

    private func loadFromUserDefaults() {
        if UserDefaults.standard.object(forKey: "yellowThreshold") != nil {
            yellowThreshold = UserDefaults.standard.integer(forKey: "yellowThreshold")
        }
        if UserDefaults.standard.object(forKey: "redThreshold") != nil {
            redThreshold = UserDefaults.standard.integer(forKey: "redThreshold")
        }
    }
}
