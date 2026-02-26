import XCTest
@testable import ClaudeUsageMenuBar

final class WeeklyCountdownCalculatorDeterministicTests: XCTestCase {

    // MARK: - Test Fixtures

    /// Creates a date for testing: Thursday, January 2, 2025 at specified time
    private func createTestDate(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 2 // Thursday
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components)!
    }

    // MARK: - extractWeekday Tests

    func testExtractWeekdaySunday() {
        XCTAssertEqual(WeeklyCountdownCalculator.extractWeekday(from: "Sun 10:00 AM"), 1)
    }

    func testExtractWeekdayMonday() {
        XCTAssertEqual(WeeklyCountdownCalculator.extractWeekday(from: "Mon 10:00 AM"), 2)
    }

    func testExtractWeekdayTuesday() {
        XCTAssertEqual(WeeklyCountdownCalculator.extractWeekday(from: "Tue 10:00 AM"), 3)
    }

    func testExtractWeekdayWednesday() {
        XCTAssertEqual(WeeklyCountdownCalculator.extractWeekday(from: "Wed 10:00 AM"), 4)
    }

    func testExtractWeekdayThursday() {
        XCTAssertEqual(WeeklyCountdownCalculator.extractWeekday(from: "Thu 10:00 AM"), 5)
    }

    func testExtractWeekdayFriday() {
        XCTAssertEqual(WeeklyCountdownCalculator.extractWeekday(from: "Fri 10:00 AM"), 6)
    }

    func testExtractWeekdaySaturday() {
        XCTAssertEqual(WeeklyCountdownCalculator.extractWeekday(from: "Sat 10:00 AM"), 7)
    }

    func testExtractWeekdayInvalidString() {
        XCTAssertNil(WeeklyCountdownCalculator.extractWeekday(from: "Invalid"))
        XCTAssertNil(WeeklyCountdownCalculator.extractWeekday(from: "10:00 AM"))
        XCTAssertNil(WeeklyCountdownCalculator.extractWeekday(from: ""))
    }

    // MARK: - extractTime Tests

    func testExtractTimeAM() {
        let result = WeeklyCountdownCalculator.extractTime(from: "Thu 10:30 AM")
        XCTAssertEqual(result?.hour, 10)
        XCTAssertEqual(result?.minute, 30)
    }

    func testExtractTimePM() {
        let result = WeeklyCountdownCalculator.extractTime(from: "Thu 3:45 PM")
        XCTAssertEqual(result?.hour, 15)
        XCTAssertEqual(result?.minute, 45)
    }

    func testExtractTime12AM() {
        let result = WeeklyCountdownCalculator.extractTime(from: "Thu 12:00 AM")
        XCTAssertEqual(result?.hour, 0)
        XCTAssertEqual(result?.minute, 0)
    }

    func testExtractTime12PM() {
        let result = WeeklyCountdownCalculator.extractTime(from: "Thu 12:00 PM")
        XCTAssertEqual(result?.hour, 12)
        XCTAssertEqual(result?.minute, 0)
    }

    func testExtractTimeLowercaseAMPM() {
        let result = WeeklyCountdownCalculator.extractTime(from: "Thu 9:15 am")
        XCTAssertEqual(result?.hour, 9)
        XCTAssertEqual(result?.minute, 15)
    }

    func testExtractTimeInvalidFormat() {
        XCTAssertNil(WeeklyCountdownCalculator.extractTime(from: "Thu"))
        XCTAssertNil(WeeklyCountdownCalculator.extractTime(from: "10:30"))
        XCTAssertNil(WeeklyCountdownCalculator.extractTime(from: "Invalid"))
    }

    // MARK: - calculateTargetDate Tests

    func testCalculateTargetDateSameDay() {
        // Thursday 9:00 AM, reset at Thursday 11:00 AM = same day
        let currentDate = createTestDate(hour: 9, minute: 0)
        let targetDate = WeeklyCountdownCalculator.calculateTargetDate(
            weekday: 5, // Thursday
            hour: 11,
            minute: 0,
            from: currentDate
        )

        XCTAssertNotNil(targetDate)
        let components = Calendar.current.dateComponents([.weekday, .hour, .minute], from: targetDate!)
        XCTAssertEqual(components.weekday, 5)
        XCTAssertEqual(components.hour, 11)
        XCTAssertEqual(components.minute, 0)
    }

    func testCalculateTargetDateNextWeek() {
        // Thursday 2:00 PM, reset at Thursday 11:00 AM = next week (same weekday)
        let currentDate = createTestDate(hour: 14, minute: 0)
        let targetDate = WeeklyCountdownCalculator.calculateTargetDate(
            weekday: 5, // Thursday
            hour: 11,
            minute: 0,
            from: currentDate
        )

        XCTAssertNotNil(targetDate)
        // Verify target is on Thursday (weekday 5) and in the future
        let targetWeekday = Calendar.current.component(.weekday, from: targetDate!)
        XCTAssertEqual(targetWeekday, 5) // Should be Thursday
        XCTAssertGreaterThan(targetDate!, currentDate) // Should be in the future

        // Target should be approximately 7 days later (6d 21hr due to 3hr difference)
        let hoursDiff = Calendar.current.dateComponents([.hour], from: currentDate, to: targetDate!).hour ?? 0
        XCTAssertGreaterThanOrEqual(hoursDiff, 165) // At least 6 days 21 hours
        XCTAssertLessThanOrEqual(hoursDiff, 168) // At most 7 days
    }

    func testCalculateTargetDateDifferentDay() {
        // Thursday 9:00 AM, reset at Monday 11:00 AM = 4 days later
        let currentDate = createTestDate(hour: 9, minute: 0)
        let targetDate = WeeklyCountdownCalculator.calculateTargetDate(
            weekday: 2, // Monday
            hour: 11,
            minute: 0,
            from: currentDate
        )

        XCTAssertNotNil(targetDate)
        let components = Calendar.current.dateComponents([.weekday, .hour, .minute], from: targetDate!)
        XCTAssertEqual(components.weekday, 2) // Monday
        XCTAssertEqual(components.hour, 11)
    }

    // MARK: - formatCountdown Tests

    func testFormatCountdownDaysHoursMinutes() {
        let currentDate = createTestDate(hour: 10, minute: 0)
        let targetDate = Calendar.current.date(byAdding: .day, value: 2, to: currentDate)!
        let adjustedTarget = Calendar.current.date(byAdding: .hour, value: 3, to: targetDate)!
        let finalTarget = Calendar.current.date(byAdding: .minute, value: 30, to: adjustedTarget)!

        let result = WeeklyCountdownCalculator.formatCountdown(from: currentDate, to: finalTarget)
        XCTAssertEqual(result, "2d 3hr 30min")
    }

    func testFormatCountdownHoursOnly() {
        let currentDate = createTestDate(hour: 10, minute: 0)
        let targetDate = Calendar.current.date(byAdding: .hour, value: 5, to: currentDate)!

        let result = WeeklyCountdownCalculator.formatCountdown(from: currentDate, to: targetDate)
        XCTAssertEqual(result, "5hr")
    }

    func testFormatCountdownMinutesOnly() {
        let currentDate = createTestDate(hour: 10, minute: 0)
        let targetDate = Calendar.current.date(byAdding: .minute, value: 45, to: currentDate)!

        let result = WeeklyCountdownCalculator.formatCountdown(from: currentDate, to: targetDate)
        XCTAssertEqual(result, "45min")
    }

    func testFormatCountdownLessThanOneMinute() {
        let currentDate = createTestDate(hour: 10, minute: 0)
        let targetDate = Calendar.current.date(byAdding: .second, value: 30, to: currentDate)!

        let result = WeeklyCountdownCalculator.formatCountdown(from: currentDate, to: targetDate)
        XCTAssertEqual(result, "< 1min")
    }

    // MARK: - Full calculate() Tests with Deterministic Date

    func testCalculateWithDeterministicDate() {
        // Thursday 9:00 AM, reset at Friday 11:00 AM
        let currentDate = createTestDate(hour: 9, minute: 0)
        let result = WeeklyCountdownCalculator.calculate(from: "Fri 11:00 AM", currentDate: currentDate)

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("1d"))
        XCTAssertTrue(result!.contains("2hr"))
    }

    func testCalculateReturnsNilForNilInput() {
        let currentDate = createTestDate(hour: 9, minute: 0)
        let result = WeeklyCountdownCalculator.calculate(from: nil, currentDate: currentDate)
        XCTAssertNil(result)
    }

    func testCalculateReturnsOriginalForInvalidFormat() {
        let currentDate = createTestDate(hour: 9, minute: 0)
        let result = WeeklyCountdownCalculator.calculate(from: "invalid", currentDate: currentDate)
        XCTAssertEqual(result, "invalid")
    }
}
