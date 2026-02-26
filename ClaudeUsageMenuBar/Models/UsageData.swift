import Foundation

struct UsageData {
    var percentage: Int?
    var messagesUsed: Int?
    var messagesLimit: Int?
    var resetTime: String?

    var weeklyPercentage: Int?
    var weeklyMessagesUsed: Int?
    var weeklyMessagesLimit: Int?
    var weeklyResetTime: String?

    var email: String?
    var organizationName: String?
    var planName: String?
    var lastUpdated: Date?
    var isLoggedIn: Bool = false
    var errorMessage: String?

    var displayPercentage: String {
        guard let percentage = percentage else { return "--" }
        return "\(percentage)%"
    }

    var usageDescription: String {
        guard let used = messagesUsed, let limit = messagesLimit else { return "" }
        return "\(used) / \(limit)"
    }

    var weeklyUsageDescription: String {
        guard let used = weeklyMessagesUsed, let limit = weeklyMessagesLimit else { return "" }
        return "\(used) / \(limit)"
    }
}
