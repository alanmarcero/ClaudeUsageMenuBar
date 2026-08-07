import XCTest
import WebKit
@testable import ClaudeUsageMenuBar

// Covers the two halves of surviving a cache_delete termination: keeping the container
// cache small enough that macOS stops picking this app, and letting the relaunch watchdog
// tell a deliberate Quit apart from a kill.
final class CacheMaintenanceTests: XCTestCase {

    // MARK: - Purge Scheduling

    func testDoesNotPurgeBeforeAnyRefreshCompletes() {
        XCTAssertFalse(CacheMaintenance.shouldPurge(refreshCount: 0))
    }

    // An upgrading user arrives with a cache already grown large, and a watchdog relaunch
    // happens while the disk is still under pressure. Both want the space back now.
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

final class QuitMarkerTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QuitMarkerTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    func testNoMarkerExistsByDefault() {
        XCTAssertFalse(QuitMarker.exists(in: directory))
    }

    func testWriteCreatesTheMarker() {
        QuitMarker.write(in: directory)
        XCTAssertTrue(QuitMarker.exists(in: directory))
    }

    func testWriteCreatesMissingDirectory() {
        let nested = directory.appendingPathComponent("Application Support")
        QuitMarker.write(in: nested)
        XCTAssertTrue(QuitMarker.exists(in: nested))
    }

    func testClearRemovesTheMarker() {
        QuitMarker.write(in: directory)
        QuitMarker.clear(in: directory)
        XCTAssertFalse(QuitMarker.exists(in: directory))
    }

    func testClearIsSafeWhenNoMarkerExists() {
        QuitMarker.clear(in: directory)
        XCTAssertFalse(QuitMarker.exists(in: directory))
    }

    func testWriteIsIdempotent() {
        QuitMarker.write(in: directory)
        QuitMarker.write(in: directory)
        XCTAssertTrue(QuitMarker.exists(in: directory))
    }

    // The watchdog shell script looks for this exact filename; renaming it here without
    // updating scripts/install-watchdog.sh would silently resurrect a deliberate Quit.
    func testMarkerFileNameMatchesTheWatchdogScript() {
        XCTAssertEqual(QuitMarker.fileName, "user-quit")
        XCTAssertEqual(QuitMarker.url(in: directory).lastPathComponent, "user-quit")
    }

    func testDefaultDirectoryResolvesInsideTheContainer() throws {
        let resolved = try XCTUnwrap(QuitMarker.defaultDirectory())
        XCTAssertTrue(resolved.path.contains("Application Support"))
        // Caches get purged by the very termination this marker outlives.
        XCTAssertFalse(resolved.path.contains("/Caches"))
    }
}
