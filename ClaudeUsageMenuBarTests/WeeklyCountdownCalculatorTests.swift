import XCTest
@testable import ClaudeUsageMenuBar

final class WeeklyCountdownCalculatorTests: XCTestCase {

    func testCalculateWithNil() {
        let result = WeeklyCountdownCalculator.calculate(from: nil)
        XCTAssertNil(result)
    }

    func testCalculateWithInvalidFormat() {
        let result = WeeklyCountdownCalculator.calculate(from: "invalid string")
        XCTAssertEqual(result, "invalid string")
    }

    func testCalculateWithMissingTime() {
        let result = WeeklyCountdownCalculator.calculate(from: "Thu")
        XCTAssertEqual(result, "Thu")
    }

    func testCalculateWithMissingDay() {
        let result = WeeklyCountdownCalculator.calculate(from: "11:00 AM")
        XCTAssertEqual(result, "11:00 AM")
    }

    func testCalculateWithValidFormat() {
        let result = WeeklyCountdownCalculator.calculate(from: "Thu 11:00 AM")
        XCTAssertNotNil(result)
        XCTAssertNotEqual(result, "Thu 11:00 AM")
        // Result should contain time units like "d", "hr", or "min"
        XCTAssertTrue(result?.contains("d") == true || result?.contains("hr") == true || result?.contains("min") == true || result == "< 1min")
    }

    func testCalculateWithPMTime() {
        let result = WeeklyCountdownCalculator.calculate(from: "Fri 3:30 PM")
        XCTAssertNotNil(result)
        XCTAssertNotEqual(result, "Fri 3:30 PM")
    }

    func testCalculateWithAllDays() {
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        for day in days {
            let result = WeeklyCountdownCalculator.calculate(from: "\(day) 10:00 AM")
            XCTAssertNotNil(result, "Failed for day: \(day)")
            XCTAssertNotEqual(result, "\(day) 10:00 AM", "Should convert \(day)")
        }
    }

    func testCalculateWith12AM() {
        let result = WeeklyCountdownCalculator.calculate(from: "Mon 12:00 AM")
        XCTAssertNotNil(result)
        XCTAssertNotEqual(result, "Mon 12:00 AM")
    }

    func testCalculateWith12PM() {
        let result = WeeklyCountdownCalculator.calculate(from: "Mon 12:00 PM")
        XCTAssertNotNil(result)
        XCTAssertNotEqual(result, "Mon 12:00 PM")
    }
}
