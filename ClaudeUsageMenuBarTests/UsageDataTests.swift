import XCTest
@testable import ClaudeUsageMenuBar

final class UsageDataTests: XCTestCase {

    func testDisplayPercentageWithValue() {
        var data = UsageData()
        data.percentage = 45
        XCTAssertEqual(data.displayPercentage, "45%")
    }

    func testDisplayPercentageWithNil() {
        let data = UsageData()
        XCTAssertEqual(data.displayPercentage, "--")
    }

    func testDisplayPercentageWithZero() {
        var data = UsageData()
        data.percentage = 0
        XCTAssertEqual(data.displayPercentage, "0%")
    }

    func testDisplayPercentageWithHundred() {
        var data = UsageData()
        data.percentage = 100
        XCTAssertEqual(data.displayPercentage, "100%")
    }

    func testDefaultValues() {
        let data = UsageData()
        XCTAssertNil(data.percentage)
        XCTAssertNil(data.weeklyPercentage)
        XCTAssertNil(data.sonnetWeeklyPercentage)
        XCTAssertNil(data.email)
        XCTAssertNil(data.organizationName)
        XCTAssertNil(data.planName)
        XCTAssertFalse(data.isLoggedIn)
    }

    // MARK: - UsageCache

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "test-usagecache-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    func testUsageCacheRoundTrip() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshot = UsageSnapshot(
            percentage: 42, resetTime: "6h 12m",
            weeklyPercentage: 80, weeklyResetTime: "3d 4h",
            sonnetWeeklyPercentage: 10, sonnetWeeklyResetTime: nil,
            designWeeklyPercentage: nil, designWeeklyResetTime: nil,
            lastUpdated: nil
        )
        UsageCache.save(snapshot, for: "claude", defaults: defaults)
        XCTAssertEqual(UsageCache.load(for: "claude", defaults: defaults), snapshot)
    }

    func testUsageCacheMissReturnsNil() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(UsageCache.load(for: "claude", defaults: defaults))
    }

    func testUsageCacheIsolatedPerProvider() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshot = UsageSnapshot(percentage: 5, resetTime: nil,
            weeklyPercentage: nil, weeklyResetTime: nil,
            sonnetWeeklyPercentage: nil, sonnetWeeklyResetTime: nil,
            designWeeklyPercentage: nil, designWeeklyResetTime: nil, lastUpdated: nil)
        UsageCache.save(snapshot, for: "claude", defaults: defaults)
        XCTAssertEqual(UsageCache.load(for: "claude", defaults: defaults)?.percentage, 5)
        XCTAssertNil(UsageCache.load(for: "codex", defaults: defaults))
    }

    func testUsageCacheClear() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshot = UsageSnapshot(percentage: 7, resetTime: nil,
            weeklyPercentage: nil, weeklyResetTime: nil,
            sonnetWeeklyPercentage: nil, sonnetWeeklyResetTime: nil,
            designWeeklyPercentage: nil, designWeeklyResetTime: nil, lastUpdated: nil)
        UsageCache.save(snapshot, for: "claude", defaults: defaults)
        UsageCache.clear(for: "claude", defaults: defaults)
        XCTAssertNil(UsageCache.load(for: "claude", defaults: defaults))
    }

    // MARK: - RelativeTime

    func testRelativeTimeJustNow() {
        let now = Date()
        XCTAssertEqual(RelativeTime.string(from: now, now: now), "just now")
        XCTAssertEqual(RelativeTime.string(from: now.addingTimeInterval(-3), now: now), "just now")
    }

    func testRelativeTimeSeconds() {
        let now = Date()
        XCTAssertEqual(RelativeTime.string(from: now.addingTimeInterval(-30), now: now), "30s ago")
    }

    func testRelativeTimeMinutes() {
        let now = Date()
        XCTAssertEqual(RelativeTime.string(from: now.addingTimeInterval(-120), now: now), "2m ago")
    }

    func testRelativeTimeHours() {
        let now = Date()
        XCTAssertEqual(RelativeTime.string(from: now.addingTimeInterval(-7200), now: now), "2h ago")
    }

    func testRelativeTimeDays() {
        let now = Date()
        XCTAssertEqual(RelativeTime.string(from: now.addingTimeInterval(-2 * 86400), now: now), "2d ago")
    }

    // MARK: - UsageTooltip

    func testUsageTooltipBoth() {
        XCTAssertEqual(UsageTooltip.line(provider: "Claude", daily: 47, weekly: 82), "Claude: 47% daily, 82% weekly")
    }

    func testUsageTooltipDailyOnly() {
        XCTAssertEqual(UsageTooltip.line(provider: "Claude", daily: 47, weekly: nil), "Claude: 47% daily")
    }

    func testUsageTooltipNoData() {
        XCTAssertEqual(UsageTooltip.line(provider: "Codex", daily: nil, weekly: nil), "Codex: no data yet")
    }

    func testIsStaleFreshData() {
        let now = Date()
        XCTAssertFalse(RelativeTime.isStale(now.addingTimeInterval(-30), now: now))
    }

    func testIsStaleOldData() {
        let now = Date()
        XCTAssertTrue(RelativeTime.isStale(now.addingTimeInterval(-300), now: now))
    }

    func testIsStaleCustomThreshold() {
        let now = Date()
        XCTAssertTrue(RelativeTime.isStale(now.addingTimeInterval(-20), now: now, threshold: 10))
        XCTAssertFalse(RelativeTime.isStale(now.addingTimeInterval(-5), now: now, threshold: 10))
    }

    func testRelativeTimeUnitBoundaries() {
        let now = Date()
        XCTAssertEqual(RelativeTime.string(from: now.addingTimeInterval(-60), now: now), "1m ago")
        XCTAssertEqual(RelativeTime.string(from: now.addingTimeInterval(-3600), now: now), "1h ago")
        XCTAssertEqual(RelativeTime.string(from: now.addingTimeInterval(-86400), now: now), "1d ago")
    }

    func testUsageTooltipWeeklyOnly() {
        XCTAssertEqual(UsageTooltip.line(provider: "Claude", daily: nil, weekly: 82), "Claude: 82% weekly")
    }

    func testIsStaleAtExactThresholdIsNotStale() {
        let now = Date()
        XCTAssertFalse(RelativeTime.isStale(now.addingTimeInterval(-120), now: now, threshold: 120))
    }
}
