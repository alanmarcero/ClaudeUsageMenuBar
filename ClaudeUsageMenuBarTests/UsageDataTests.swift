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
}
