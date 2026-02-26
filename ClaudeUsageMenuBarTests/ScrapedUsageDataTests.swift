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

    // MARK: - Usage Description Tests

    func testUsageDescriptionFormatsCorrectly() {
        var data = UsageData()
        data.messagesUsed = 15
        data.messagesLimit = 45
        XCTAssertEqual(data.usageDescription, "15 / 45")
    }

    func testUsageDescriptionHandlesLargeNumbers() {
        var data = UsageData()
        data.messagesUsed = 1500
        data.messagesLimit = 4500
        XCTAssertEqual(data.usageDescription, "1500 / 4500")
    }

    func testUsageDescriptionEmptyWhenUsedIsNil() {
        var data = UsageData()
        data.messagesLimit = 45
        XCTAssertEqual(data.usageDescription, "")
    }

    func testUsageDescriptionEmptyWhenLimitIsNil() {
        var data = UsageData()
        data.messagesUsed = 15
        XCTAssertEqual(data.usageDescription, "")
    }

    // MARK: - Weekly Usage Description Tests

    func testWeeklyUsageDescriptionFormatsCorrectly() {
        var data = UsageData()
        data.weeklyMessagesUsed = 100
        data.weeklyMessagesLimit = 500
        XCTAssertEqual(data.weeklyUsageDescription, "100 / 500")
    }

    func testWeeklyUsageDescriptionEmptyWhenNil() {
        let data = UsageData()
        XCTAssertEqual(data.weeklyUsageDescription, "")
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
    }

    // MARK: - Full Data State Tests

    func testFullyPopulatedData() {
        var data = UsageData()
        data.percentage = 50
        data.messagesUsed = 25
        data.messagesLimit = 50
        data.resetTime = "5 hours"
        data.weeklyPercentage = 30
        data.weeklyMessagesUsed = 150
        data.weeklyMessagesLimit = 500
        data.weeklyResetTime = "Thu 11:00 AM"
        data.email = "user@example.com"
        data.organizationName = "Acme Corp"
        data.planName = "Pro"
        data.isLoggedIn = true
        data.lastUpdated = Date()

        XCTAssertEqual(data.displayPercentage, "50%")
        XCTAssertEqual(data.usageDescription, "25 / 50")
        XCTAssertEqual(data.weeklyUsageDescription, "150 / 500")
        XCTAssertTrue(data.isLoggedIn)
        XCTAssertNotNil(data.lastUpdated)
    }
}
