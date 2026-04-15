import Foundation

struct UsageData {
    var percentage: Int?
    var resetTime: String?

    var weeklyPercentage: Int?
    var weeklyResetTime: String?

    var sonnetWeeklyPercentage: Int?
    var sonnetWeeklyResetTime: String?

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
}
