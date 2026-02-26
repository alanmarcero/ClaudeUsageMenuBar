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

    func testUsageDescriptionWithValues() {
        var data = UsageData()
        data.messagesUsed = 25
        data.messagesLimit = 100
        XCTAssertEqual(data.usageDescription, "25 / 100")
    }

    func testUsageDescriptionWithNilUsed() {
        var data = UsageData()
        data.messagesLimit = 100
        XCTAssertEqual(data.usageDescription, "")
    }

    func testUsageDescriptionWithNilLimit() {
        var data = UsageData()
        data.messagesUsed = 25
        XCTAssertEqual(data.usageDescription, "")
    }

    func testUsageDescriptionWithBothNil() {
        let data = UsageData()
        XCTAssertEqual(data.usageDescription, "")
    }

    func testWeeklyUsageDescriptionWithValues() {
        var data = UsageData()
        data.weeklyMessagesUsed = 50
        data.weeklyMessagesLimit = 200
        XCTAssertEqual(data.weeklyUsageDescription, "50 / 200")
    }

    func testWeeklyUsageDescriptionWithNil() {
        let data = UsageData()
        XCTAssertEqual(data.weeklyUsageDescription, "")
    }

    func testDefaultValues() {
        let data = UsageData()
        XCTAssertNil(data.percentage)
        XCTAssertNil(data.messagesUsed)
        XCTAssertNil(data.messagesLimit)
        XCTAssertNil(data.email)
        XCTAssertNil(data.organizationName)
        XCTAssertFalse(data.isLoggedIn)
    }
}
