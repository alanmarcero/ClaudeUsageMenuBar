import XCTest
@testable import ClaudeUsageMenuBar

final class CursorUsageAPITests: XCTestCase {

    private let eastern = TimeZone(identifier: "America/New_York")!

    // Enterprise summary: the two pools are the percent fields. Team on-demand
    // is not the user's own spend, so the personal bucket stays at zero.
    private let enterpriseBody = """
    {
      "billingCycleEnd": "2026-12-20T16:25:10.000Z",
      "membershipType": "enterprise",
      "individualUsage": {
        "plan": {
          "enabled": true,
          "used": 2000,
          "limit": 2000,
          "autoPercentUsed": 3.9095238095238094,
          "apiPercentUsed": 59.714999999999996,
          "totalPercentUsed": 12.8384
        },
        "onDemand": { "enabled": true, "used": 0, "limit": null }
      },
      "teamUsage": { "onDemand": { "enabled": true, "used": 145292, "limit": 2040000 } }
    }
    """

    func testUsageResultMapsPoolsResetAndPersonalOnDemand() {
        let result = CursorUsageAPI.usageResult(from: Data(enterpriseBody.utf8), httpStatus: 200, timeZone: eastern)

        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(result["percentage"] as? Int, 13)
        XCTAssertEqual(result["weeklyPercentage"] as? Int, 60)
        XCTAssertEqual(result["sonnetWeeklyPercentage"] as? Int, 4)
        XCTAssertEqual(result["sonnetWeeklyLabel"] as? String, "Cursor Models")
        XCTAssertEqual(result["resetTime"] as? String, "Resets Dec 20, 2026 11:25 AM")
        XCTAssertEqual(result["weeklyResetTime"] as? String, "Resets Dec 20, 2026 11:25 AM")
        XCTAssertEqual(result["planName"] as? String, "Enterprise")
        XCTAssertEqual(result["onDemandUsed"] as? Double ?? -1, 0, accuracy: 0.001)
    }

    func testUsageResultPrefersPersonalOnDemandWhenTheUserHasSpend() {
        let body = """
        {
          "billingCycleEnd": "2026-12-20T16:25:10.000Z",
          "membershipType": "pro_plus",
          "individualUsage": {
            "plan": { "autoPercentUsed": 10, "apiPercentUsed": 90, "totalPercentUsed": 15.4 },
            "onDemand": { "enabled": true, "used": 1234, "limit": null }
          },
          "teamUsage": { "onDemand": { "used": 86000, "limit": 1000000 } }
        }
        """

        let result = CursorUsageAPI.usageResult(from: Data(body.utf8), httpStatus: 200, timeZone: eastern)

        XCTAssertEqual(result["onDemandUsed"] as? Double ?? 0, 12.34, accuracy: 0.001)
        XCTAssertEqual(result["planName"] as? String, "Pro Plus")
        XCTAssertEqual(result["percentage"] as? Int, 15)
    }

    func testUsageResultKeepsZeroPersonalOnDemandWhenALimitIsSet() {
        let body = """
        {
          "individualUsage": {
            "plan": { "totalPercentUsed": 1, "apiPercentUsed": 0, "autoPercentUsed": 1 },
            "onDemand": { "enabled": true, "used": 0, "limit": 2000 }
          }
        }
        """

        let result = CursorUsageAPI.usageResult(from: Data(body.utf8), httpStatus: 200)

        XCTAssertEqual(result["onDemandUsed"] as? Double ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(result["weeklyPercentage"] as? Int, 0)
        XCTAssertEqual(result["sonnetWeeklyPercentage"] as? Int, 1)
    }

    func testUsageResultFallsBackToCentsWhenPercentsAreMissing() {
        let body = """
        { "individualUsage": { "plan": { "used": 500, "limit": 2000 } } }
        """

        let result = CursorUsageAPI.usageResult(from: Data(body.utf8), httpStatus: 200)

        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(result["percentage"] as? Int, 25)
        XCTAssertNil(result["sonnetWeeklyLabel"] as? String)
    }

    func testUsageResultOn401ReportsExpiredLogin() {
        let result = CursorUsageAPI.usageResult(from: Data(), httpStatus: 401)

        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertEqual(result["error"] as? String, CursorUsageAPI.expiredLoginMessage)
    }

    func testUsageResultOnServerErrorReportsStatus() {
        let result = CursorUsageAPI.usageResult(from: Data("busy".utf8), httpStatus: 503)

        XCTAssertEqual(result["error"] as? String, "Cursor usage request failed (HTTP 503). Will retry automatically.")
    }

    func testSessionCookieUsesTheSubjectUserID() {
        let token = jwt(["sub": "auth0|user_abc", "exp": 1_900_000_000])

        let cookie = CursorUsageAPI.sessionCookie(for: token)

        XCTAssertEqual(cookie, "WorkosCursorSessionToken=user_abc%3A%3A\(token.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"))!)")
    }

    func testFetchResultWithExpiredLoginSkipsTheRequest() async {
        let login = CursorUsageAPI.Login(accessToken: jwt(["sub": "auth0|user_abc", "exp": 100]), expiresAt: Date(timeIntervalSince1970: 100))

        let result = await CursorUsageAPI.fetchResult(login: login, now: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertEqual(result["error"] as? String, CursorUsageAPI.expiredLoginMessage)
    }

    private func jwt(_ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "e30.\(encoded).sig"
    }
}
