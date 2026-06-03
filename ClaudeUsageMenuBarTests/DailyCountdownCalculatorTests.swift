import XCTest
@testable import ClaudeUsageMenuBar

final class DailyCountdownCalculatorTests: XCTestCase {

    /// Thursday, January 2, 2025 at the specified time.
    private func createTestDate(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 2
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)!
    }

    func testNilReturnsNil() {
        XCTAssertNil(DailyCountdownCalculator.calculate(from: nil))
    }

    func testClockTimeLaterTodayCountsDown() {
        let now = createTestDate(hour: 14, minute: 0)
        XCTAssertEqual(DailyCountdownCalculator.calculate(from: "Resets 9:55 PM", currentDate: now), "7hr 55min")
    }

    func testClockTimeAlreadyPassedRollsToTomorrow() {
        let now = createTestDate(hour: 22, minute: 0)
        XCTAssertEqual(DailyCountdownCalculator.calculate(from: "Resets 9:55 PM", currentDate: now), "23hr 55min")
    }

    func testMidnightResetCountsToNextMidnight() {
        let now = createTestDate(hour: 14, minute: 0)
        XCTAssertEqual(DailyCountdownCalculator.calculate(from: "Resets 12:00 AM", currentDate: now), "10hr")
    }

    func testRelativeStringPassesThroughUnchanged() {
        // Claude's daily reset arrives already relative; no clock time to convert.
        let now = createTestDate(hour: 14, minute: 0)
        XCTAssertEqual(DailyCountdownCalculator.calculate(from: "Resets in 2 hr 40 min", currentDate: now), "Resets in 2 hr 40 min")
    }

    func testJustPastResetRollsToTomorrow() {
        let now = createTestDate(hour: 21, minute: 56)
        XCTAssertEqual(DailyCountdownCalculator.calculate(from: "Resets 9:55 PM", currentDate: now), "23hr 59min")
    }
}
