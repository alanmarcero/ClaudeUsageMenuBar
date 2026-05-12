import XCTest
@testable import ClaudeUsageMenuBar

@MainActor
final class RefreshTimeoutTests: XCTestCase {

    // MARK: - Test Fixtures

    private func createFixedDate() -> Date {
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 15
        components.hour = 10
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components)!
    }

    // MARK: - Constants Tests

    func testRefreshTimeoutConstantValue() {
        XCTAssertEqual(UsageService.Constants.refreshTimeout, 30)
    }

    func testRefreshIntervalConstantValue() {
        XCTAssertEqual(UsageService.Constants.refreshInterval, 30)
    }

    // MARK: - checkForRefreshTimeout Tests

    func testCheckForRefreshTimeoutDoesNothingWhenStartTimeNil() {
        let service = UsageService()
        service.refreshStartTime = nil
        service.isRefreshing = true

        service.checkForRefreshTimeout(currentDate: createFixedDate())

        XCTAssertTrue(service.isRefreshing)
        XCTAssertNil(service.usageData.errorMessage)
    }

    func testCheckForRefreshTimeoutDoesNothingWithinTimeout() {
        let service = UsageService()
        let fixedDate = createFixedDate()
        service.refreshStartTime = fixedDate
        service.isRefreshing = true

        // Check at same time - 0 seconds elapsed
        service.checkForRefreshTimeout(currentDate: fixedDate)

        XCTAssertTrue(service.isRefreshing)
        XCTAssertNil(service.usageData.errorMessage)
    }

    func testCheckForRefreshTimeoutDoesNothingAt29Seconds() {
        let service = UsageService()
        let startTime = createFixedDate()
        let checkTime = startTime.addingTimeInterval(29)
        service.refreshStartTime = startTime
        service.isRefreshing = true

        service.checkForRefreshTimeout(currentDate: checkTime)

        XCTAssertTrue(service.isRefreshing)
        XCTAssertNil(service.usageData.errorMessage)
    }

    func testCheckForRefreshTimeoutTriggersRecoveryWhenExceeded() {
        let service = UsageService()
        let startTime = createFixedDate()
        let checkTime = startTime.addingTimeInterval(35)
        service.refreshStartTime = startTime
        service.isRefreshing = true

        service.checkForRefreshTimeout(currentDate: checkTime)

        XCTAssertFalse(service.isRefreshing)
        XCTAssertNil(service.refreshStartTime)
        XCTAssertEqual(service.usageData.errorMessage, "Refresh timed out. Will retry automatically.")
    }

    // MARK: - recoverFromStuckRefresh Tests

    func testRecoverFromStuckRefreshResetsIsRefreshing() {
        let service = UsageService()
        service.isRefreshing = true

        service.recoverFromStuckRefresh()

        XCTAssertFalse(service.isRefreshing)
    }

    func testRecoverFromStuckRefreshClearsRefreshStartTime() {
        let service = UsageService()
        service.refreshStartTime = createFixedDate()

        service.recoverFromStuckRefresh()

        XCTAssertNil(service.refreshStartTime)
    }

    func testRecoverFromStuckRefreshSetsErrorMessage() {
        let service = UsageService()

        service.recoverFromStuckRefresh()

        XCTAssertEqual(service.usageData.errorMessage, "Refresh timed out. Will retry automatically.")
    }

    // MARK: - setError Tests

    func testSetErrorClearsRefreshStartTime() {
        let service = UsageService()
        service.refreshStartTime = createFixedDate()

        service.setError("Test error")

        XCTAssertNil(service.refreshStartTime)
    }

    func testSetErrorResetsIsRefreshing() {
        let service = UsageService()
        service.isRefreshing = true

        service.setError("Test error")

        XCTAssertFalse(service.isRefreshing)
    }

    // MARK: - setLoggedOut Tests

    func testSetLoggedOutClearsRefreshStartTime() {
        let service = UsageService()
        service.refreshStartTime = createFixedDate()

        service.setLoggedOut()

        XCTAssertNil(service.refreshStartTime)
    }

    func testSetLoggedOutResetsIsRefreshing() {
        let service = UsageService()
        service.isRefreshing = true

        service.setLoggedOut()

        XCTAssertFalse(service.isRefreshing)
    }

    // MARK: - Boundary Tests

    func testTimeoutAtExactBoundary() {
        let service = UsageService()
        let startTime = createFixedDate()
        let checkTime = startTime.addingTimeInterval(UsageService.Constants.refreshTimeout)
        service.refreshStartTime = startTime
        service.isRefreshing = true

        service.checkForRefreshTimeout(currentDate: checkTime)

        // At exactly the boundary, should NOT trigger (> not >=)
        XCTAssertTrue(service.isRefreshing)
    }

    func testTimeoutJustOverBoundary() {
        let service = UsageService()
        let startTime = createFixedDate()
        let checkTime = startTime.addingTimeInterval(UsageService.Constants.refreshTimeout + 0.1)
        service.refreshStartTime = startTime
        service.isRefreshing = true

        service.checkForRefreshTimeout(currentDate: checkTime)

        XCTAssertFalse(service.isRefreshing)
    }
}
