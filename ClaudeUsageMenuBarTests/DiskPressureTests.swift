import XCTest
import WebKit
@testable import ClaudeUsageMenuBar

// Keeping the container cache small is what stops macOS from picking this app when
// cache_delete goes looking for space to reclaim.
final class CacheMaintenanceTests: XCTestCase {

    // MARK: - Purge Scheduling

    func testDoesNotPurgeBeforeAnyRefreshCompletes() {
        XCTAssertFalse(CacheMaintenance.shouldPurge(refreshCount: 0))
    }

    // An upgrading user arrives with a cache already grown large, and an app reopened after
    // a termination starts up with the disk still under pressure. Both want the space back now.
    func testPurgesOnFirstRefreshAfterLaunch() {
        XCTAssertTrue(CacheMaintenance.shouldPurge(refreshCount: 1))
    }

    func testDoesNotPurgeAgainImmediatelyAfterTheLaunchPurge() {
        XCTAssertFalse(CacheMaintenance.shouldPurge(refreshCount: 2))
        XCTAssertFalse(CacheMaintenance.shouldPurge(refreshCount: 3))
    }

    func testPurgesOnTheIntervalRefresh() {
        XCTAssertTrue(CacheMaintenance.shouldPurge(refreshCount: CacheMaintenance.purgeEveryNRefreshes))
    }

    func testDoesNotPurgeOnRefreshBeforeInterval() {
        XCTAssertFalse(CacheMaintenance.shouldPurge(refreshCount: CacheMaintenance.purgeEveryNRefreshes - 1))
    }

    func testDoesNotPurgeOnRefreshAfterInterval() {
        XCTAssertFalse(CacheMaintenance.shouldPurge(refreshCount: CacheMaintenance.purgeEveryNRefreshes + 1))
    }

    func testPurgesOnEveryMultipleOfInterval() {
        let interval = CacheMaintenance.purgeEveryNRefreshes
        for multiple in 1...5 {
            XCTAssertTrue(
                CacheMaintenance.shouldPurge(refreshCount: interval * multiple),
                "expected a purge at refresh \(interval * multiple)"
            )
        }
    }

    func testHonorsCustomInterval() {
        XCTAssertTrue(CacheMaintenance.shouldPurge(refreshCount: 3, every: 3))
        XCTAssertFalse(CacheMaintenance.shouldPurge(refreshCount: 2, every: 3))
    }

    func testNeverPurgesWithNonPositiveInterval() {
        XCTAssertFalse(CacheMaintenance.shouldPurge(refreshCount: 10, every: 0))
        XCTAssertFalse(CacheMaintenance.shouldPurge(refreshCount: 10, every: -1))
    }

    func testIgnoresNegativeRefreshCount() {
        XCTAssertFalse(CacheMaintenance.shouldPurge(refreshCount: -120))
    }

    func testDefaultIntervalIsRoughlyHourly() {
        let secondsPerHour = 3600.0
        let expected = Int(secondsPerHour / UsageService.Constants.refreshInterval)
        XCTAssertEqual(CacheMaintenance.purgeEveryNRefreshes, expected)
    }

    // MARK: - Purge Scope

    // The whole point of a scoped purge: the response caches are what grow, and the session
    // must survive. Purging cookies or local storage would log the user out on a timer.
    func testPurgesTheResponseCachesThatGrow() {
        XCTAssertTrue(CacheMaintenance.httpCacheDataTypes.contains(WKWebsiteDataTypeDiskCache))
        XCTAssertTrue(CacheMaintenance.httpCacheDataTypes.contains(WKWebsiteDataTypeFetchCache))
        XCTAssertTrue(CacheMaintenance.httpCacheDataTypes.contains(WKWebsiteDataTypeMemoryCache))
    }

    func testNeverPurgesTheSignedInSession() {
        XCTAssertFalse(CacheMaintenance.httpCacheDataTypes.contains(WKWebsiteDataTypeCookies))
        XCTAssertFalse(CacheMaintenance.httpCacheDataTypes.contains(WKWebsiteDataTypeLocalStorage))
        XCTAssertFalse(CacheMaintenance.httpCacheDataTypes.contains(WKWebsiteDataTypeSessionStorage))
        XCTAssertFalse(CacheMaintenance.httpCacheDataTypes.contains(WKWebsiteDataTypeIndexedDBDatabases))
    }

    func testPurgeScopeIsNarrowerThanLogout() {
        XCTAssertTrue(CacheMaintenance.httpCacheDataTypes.isSubset(of: WKWebsiteDataStore.allWebsiteDataTypes()))
        XCTAssertLessThan(CacheMaintenance.httpCacheDataTypes.count, WKWebsiteDataStore.allWebsiteDataTypes().count)
    }
}
