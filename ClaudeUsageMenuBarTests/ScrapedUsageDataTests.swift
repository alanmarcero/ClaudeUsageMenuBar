import XCTest
@testable import ClaudeUsageMenuBar

final class ScrapedUsageDataTests: XCTestCase {

    // MARK: - UsageData Display Tests

    func testDisplayPercentageFormatsCorrectly() {
        var data = UsageData()
        data.percentage = 75
        XCTAssertEqual(data.displayPercentage, "75%")
    }

    func testDisplayPercentageHandlesZero() {
        var data = UsageData()
        data.percentage = 0
        XCTAssertEqual(data.displayPercentage, "0%")
    }

    func testDisplayPercentageHandles100() {
        var data = UsageData()
        data.percentage = 100
        XCTAssertEqual(data.displayPercentage, "100%")
    }

    func testDisplayPercentageHandlesNil() {
        let data = UsageData()
        XCTAssertEqual(data.displayPercentage, "--")
    }

    // MARK: - Default State Tests

    func testDefaultStateIsLoggedOut() {
        let data = UsageData()
        XCTAssertFalse(data.isLoggedIn)
    }

    func testDefaultStateHasNoError() {
        let data = UsageData()
        XCTAssertNil(data.errorMessage)
    }

    func testDefaultStateHasNoPercentages() {
        let data = UsageData()
        XCTAssertNil(data.percentage)
        XCTAssertNil(data.weeklyPercentage)
        XCTAssertNil(data.sonnetWeeklyPercentage)
    }

    func testDefaultStateHasNoAccountInfo() {
        let data = UsageData()
        XCTAssertNil(data.email)
        XCTAssertNil(data.organizationName)
        XCTAssertNil(data.planName)
    }

    func testDefaultStateHasNoResetTimes() {
        let data = UsageData()
        XCTAssertNil(data.resetTime)
        XCTAssertNil(data.weeklyResetTime)
        XCTAssertNil(data.sonnetWeeklyResetTime)
    }

    // MARK: - Full Data State Tests

    func testFullyPopulatedData() {
        var data = UsageData()
        data.percentage = 50
        data.resetTime = "5 hours"
        data.weeklyPercentage = 30
        data.weeklyResetTime = "Thu 11:00 AM"
        data.sonnetWeeklyPercentage = 10
        data.sonnetWeeklyResetTime = "Mon 11:00 AM"
        data.email = "user@example.com"
        data.organizationName = "Acme Corp"
        data.planName = "Team"
        data.isLoggedIn = true
        data.lastUpdated = Date()

        XCTAssertEqual(data.displayPercentage, "50%")
        XCTAssertEqual(data.weeklyPercentage, 30)
        XCTAssertEqual(data.sonnetWeeklyPercentage, 10)
        XCTAssertEqual(data.weeklyResetTime, "Thu 11:00 AM")
        XCTAssertEqual(data.sonnetWeeklyResetTime, "Mon 11:00 AM")
        XCTAssertEqual(data.planName, "Team")
        XCTAssertTrue(data.isLoggedIn)
        XCTAssertNotNil(data.lastUpdated)
    }
}
