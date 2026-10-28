import Foundation

struct UsageData {
    var percentage: Int?
    var resetTime: String?

    var weeklyPercentage: Int?
    var weeklyResetTime: String?

    var sonnetWeeklyPercentage: Int?
    var sonnetWeeklyResetTime: String?
    var sonnetWeeklyLabel: String?

    var designWeeklyPercentage: Int?
    var designWeeklyResetTime: String?
    var designWeeklyLabel: String?

    var email: String?
    var organizationName: String?
    var planName: String?
    var availableResets: Int?
    var creditsUsed: Double?
    var creditsLimit: Double?
    var lastUpdated: Date?
    var isLoggedIn: Bool = false
    var errorMessage: String?

    var displayPercentage: String {
        guard let percentage = percentage ?? weeklyPercentage else { return "--" }
        return "\(percentage)%"
    }

    var hasDailyLimit: Bool {
        percentage != nil || resetTime != nil
    }
}

// A persisted snapshot of the last successful scrape so the menu bar can show the
// previous percentage immediately on launch instead of "--" while it re-fetches.
struct UsageSnapshot: Codable, Equatable {
    var percentage: Int?
    var resetTime: String?
    var weeklyPercentage: Int?
    var weeklyResetTime: String?
    var sonnetWeeklyPercentage: Int?
    var sonnetWeeklyResetTime: String?
    var designWeeklyPercentage: Int?
    var designWeeklyResetTime: String?
    var sonnetWeeklyLabel: String?
    var designWeeklyLabel: String?
    var creditsUsed: Double?
    var creditsLimit: Double?
    var lastUpdated: Date?
}

// Stores/loads the last UsageSnapshot per provider. `defaults` is injectable for tests.
enum UsageCache {
    static func key(for providerID: String) -> String { "lastUsageSnapshot.\(providerID)" }

    static func save(_ snapshot: UsageSnapshot, for providerID: String, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key(for: providerID))
    }

    static func load(for providerID: String, defaults: UserDefaults = .standard) -> UsageSnapshot? {
        guard let data = defaults.data(forKey: key(for: providerID)) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    static func clear(for providerID: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(for: providerID))
    }
}

// Builds the menu-bar icon's hover tooltip line for one provider, e.g.
// "Claude: 47% daily, 82% weekly".
enum UsageTooltip {
    static func line(provider: String, daily: Int?, weekly: Int?) -> String {
        var parts: [String] = []
        if let daily { parts.append("\(daily)% daily") }
        if let weekly { parts.append("\(weekly)% weekly") }
        return parts.isEmpty ? "\(provider): no data yet" : "\(provider): \(parts.joined(separator: ", "))"
    }
}

// OpenAI publishes no credit price.
// Its Codex pricing page bills desktop voice at $0.05 or 1.25 credits a minute.
enum CreditUsage {
    static let dollarsPerCredit = 0.04

    static func percentage(used: Double, limit: Double) -> Int? {
        limit > 0 ? Int((used / limit * 100).rounded()) : nil
    }

    static func summary(used: Double, limit: Double) -> String {
        "\(wholeNumber(used)) of \(wholeNumber(limit)) monthly credits used"
    }

    static func estimatedSpend(used: Double) -> String {
        let spend = (used * dollarsPerCredit).formatted(.currency(code: "USD"))
        let rate = dollarsPerCredit.formatted(.currency(code: "USD"))
        return "≈ \(spend) spent at \(rate) per credit"
    }

    private static func wholeNumber(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.grouping(.automatic))
    }
}

// Compact "x ago" formatting for the last-updated indicator. `now` is injectable for tests.
enum RelativeTime {
    static func string(from date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    // Data older than `threshold` means refreshes have been missing (logged out, error,
    // or a snapshot restored from a previous session) — worth flagging visually.
    static func isStale(_ date: Date, now: Date = Date(), threshold: TimeInterval = 120) -> Bool {
        now.timeIntervalSince(date) > threshold
    }
}
