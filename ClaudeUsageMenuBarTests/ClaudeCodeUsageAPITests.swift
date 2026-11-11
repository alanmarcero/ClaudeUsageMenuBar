import XCTest
@testable import ClaudeUsageMenuBar

final class ClaudeCodeUsageAPITests: XCTestCase {

    private let eastern = TimeZone(identifier: "America/New_York")!

    private let usageBody = """
    {
      "five_hour": {"utilization": 5.0, "resets_at": "2026-10-21T18:10:00.219432+00:00"},
      "limits": [
        {"kind": "session", "percent": 5, "resets_at": "2026-10-21T18:10:00.219432+00:00", "scope": null},
        {"kind": "weekly_all", "percent": 14.4, "resets_at": "2026-10-25T07:00:00.219453+00:00", "scope": null},
        {"kind": "weekly_scoped", "percent": 0, "resets_at": "2026-10-25T07:00:00+00:00",
         "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}},
        {"kind": "weekly_scoped", "percent": 30, "resets_at": "2026-10-25T07:00:00+00:00",
         "scope": {"model": {"id": null, "display_name": "Sonnet"}, "surface": null}}
      ]
    }
    """

    // MARK: - parseLogin

    func testParseLoginReadsTokenExpiryAndPlan() {
        let data = Data(#"{"claudeAiOauth": {"accessToken": "fake-token", "expiresAt": 1792609892000, "subscriptionType": "team"}}"#.utf8)

        let login = ClaudeCodeUsageAPI.parseLogin(data)

        XCTAssertEqual(login, ClaudeCodeUsageAPI.Login(
            accessToken: "fake-token",
            expiresAt: Date(timeIntervalSince1970: 1_792_609_892),
            subscriptionType: "team"
        ))
    }

    func testParseLoginWithoutClaudeAiOauthReturnsNil() {
        let data = Data(#"{"mcpOAuth": {"server": {"accessToken": "fake-token"}}}"#.utf8)

        XCTAssertNil(ClaudeCodeUsageAPI.parseLogin(data))
    }

    func testParseLoginWithEmptyTokenReturnsNil() {
        let data = Data(#"{"claudeAiOauth": {"accessToken": ""}}"#.utf8)

        XCTAssertNil(ClaudeCodeUsageAPI.parseLogin(data))
    }

    // MARK: - usageResult

    func testUsageResultMapsSessionWeeklyAndScopedLimits() {
        let result = ClaudeCodeUsageAPI.usageResult(from: Data(usageBody.utf8), httpStatus: 200, planName: "Team", timeZone: eastern)

        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(result["percentage"] as? Int, 5)
        XCTAssertEqual(result["resetTime"] as? String, "Resets Oct 21, 2026 2:10 PM")
        XCTAssertEqual(result["weeklyPercentage"] as? Int, 14)
        XCTAssertEqual(result["weeklyResetTime"] as? String, "Resets Oct 25, 2026 3:00 AM")
        XCTAssertEqual(result["sonnetWeeklyPercentage"] as? Int, 30)
        XCTAssertEqual(result["sonnetWeeklyLabel"] as? String, "Weekly (Sonnet)")
        XCTAssertEqual(result["planName"] as? String, "Team")
    }

    func testUsageResultDropsHiddenScopedLimitAndLeavesSecondSlotEmpty() {
        let result = ClaudeCodeUsageAPI.usageResult(from: Data(usageBody.utf8), httpStatus: 200, planName: nil, timeZone: eastern)

        XCTAssertNil(result["designWeeklyPercentage"] as? Int)
        XCTAssertNil(result["designWeeklyLabel"] as? String)
    }

    func testUsageResultOn401ReportsExpiredLogin() {
        let result = ClaudeCodeUsageAPI.usageResult(from: Data(), httpStatus: 401, planName: nil)

        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertEqual(result["error"] as? String, ClaudeCodeUsageAPI.expiredLoginMessage)
    }

    func testUsageResultOnServerErrorReportsStatus() {
        let result = ClaudeCodeUsageAPI.usageResult(from: Data("busy".utf8), httpStatus: 503, planName: nil)

        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertEqual(result["error"] as? String, "Claude usage request failed (HTTP 503). Will retry automatically.")
    }

    func testUsageResultWithoutLimitsFails() {
        let result = ClaudeCodeUsageAPI.usageResult(from: Data(#"{"limits": []}"#.utf8), httpStatus: 200, planName: nil)

        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertNotNil(result["error"] as? String)
    }

    func testUsageResultDebugRecordsStatusAndBody() {
        let result = ClaudeCodeUsageAPI.usageResult(from: Data(usageBody.utf8), httpStatus: 200, planName: nil)

        let debug = result["debug"] as? String ?? ""
        XCTAssertTrue(debug.contains("\"httpStatus\" : 200"))
        XCTAssertTrue(debug.contains("weekly_scoped"))
    }

    // MARK: - fetchResult

    func testFetchResultWithExpiredLoginSkipsTheRequest() async {
        let login = ClaudeCodeUsageAPI.Login(accessToken: "fake-token", expiresAt: Date(timeIntervalSince1970: 100), subscriptionType: nil)

        let result = await ClaudeCodeUsageAPI.fetchResult(login: login, now: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertEqual(result["error"] as? String, ClaudeCodeUsageAPI.expiredLoginMessage)
    }

    // MARK: - resetText

    func testResetTextConvertsISODateToLocalAbsoluteTime() {
        let text = ClaudeCodeUsageAPI.resetText(fromISODate: "2026-10-25T07:00:00.219453+00:00", timeZone: eastern)

        XCTAssertEqual(text, "Resets Oct 25, 2026 3:00 AM")
    }

    func testResetTextRoundsToTheNearestMinute() {
        let text = ClaudeCodeUsageAPI.resetText(fromISODate: "2026-10-25T06:59:59.912345+00:00", timeZone: eastern)

        XCTAssertEqual(text, "Resets Oct 25, 2026 3:00 AM")
    }

    func testResetTextWithInvalidDateReturnsNil() {
        XCTAssertNil(ClaudeCodeUsageAPI.resetText(fromISODate: "soon", timeZone: eastern))
    }

    // MARK: - resetFields

    func testUsageResultListsOneResetPerRedeemableReset() {
        let body = """
        {"limits": [{"kind": "session", "percent": 5, "resets_at": null, "scope": null}],
         "cedar_ember": {"eligible": true, "grants": [
           {"id": "g1", "label": "Full reset", "resets_left": 2, "ends_at": "2026-11-12T22:12:00Z"},
           {"id": "g2", "label": "", "resets_left": 1, "ends_at": null},
           {"id": "g3", "label": "Weekly reset", "resets_left": 0, "ends_at": "2026-11-20T22:12:00Z"}
         ]}}
        """

        let result = ClaudeCodeUsageAPI.usageResult(from: Data(body.utf8), httpStatus: 200, planName: nil, timeZone: eastern)

        XCTAssertEqual(result["availableResets"] as? Int, 3)
        XCTAssertEqual(UsageReset.list(from: result["resets"]), [
            UsageReset(title: "Full reset", expires: "Nov 12 at 5:12 PM EST"),
            UsageReset(title: "Full reset", expires: "Nov 12 at 5:12 PM EST"),
            UsageReset(title: nil, expires: nil)
        ])
    }

    func testUsageResultWithoutResetBlockLeavesResetsUnset() {
        let result = ClaudeCodeUsageAPI.usageResult(from: Data(usageBody.utf8), httpStatus: 200, planName: nil, timeZone: eastern)

        XCTAssertNil(result["availableResets"])
    }

    func testUsageURLAsksForTheResetBlock() {
        XCTAssertEqual(ClaudeCodeUsageAPI.usageURL.query, "cedar_ember=1")
    }

    func testUsageResultWithIneligibleResetBlockLeavesResetsUnset() {
        let body = """
        {"limits": [{"kind": "session", "percent": 5, "resets_at": null, "scope": null}],
         "cedar_ember": {"eligible": false, "ineligible_reason": "surface", "grants": []}}
        """

        let result = ClaudeCodeUsageAPI.usageResult(from: Data(body.utf8), httpStatus: 200, planName: nil, timeZone: eastern)

        XCTAssertNil(result["availableResets"])
    }
}
