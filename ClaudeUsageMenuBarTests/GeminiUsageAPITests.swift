import XCTest
@testable import ClaudeUsageMenuBar

final class GeminiUsageAPITests: XCTestCase {

    private let eastern = TimeZone(identifier: "America/New_York")!

    private let quotaBody = """
    {
      "groups": [
        {
          "buckets": [
            {
              "bucketId": "gemini-weekly",
              "displayName": "Weekly Limit Remaining",
              "window": "weekly",
              "resetTime": "2026-11-11T20:23:00Z",
              "remainingFraction": 0.98265845
            },
            {
              "bucketId": "gemini-5h",
              "displayName": "Five Hour Limit Remaining",
              "window": "5h",
              "resetTime": "2026-11-06T04:08:12Z",
              "remainingFraction": 0.97083074
            }
          ],
          "displayName": "Gemini Models"
        },
        {
          "buckets": [
            {
              "bucketId": "3p-weekly",
              "displayName": "Weekly Limit Remaining",
              "window": "weekly",
              "resetTime": "2026-11-13T02:27:55Z",
              "remainingFraction": 1
            },
            {
              "bucketId": "3p-5h",
              "displayName": "Five Hour Limit Remaining",
              "window": "5h",
              "resetTime": "2026-11-06T07:27:55Z",
              "remainingFraction": 1
            }
          ],
          "displayName": "Claude and GPT models"
        },
        {
          "buckets": [
            {
              "bucketId": "gemini-argon-wtu-weekly",
              "displayName": "Gemini 4 Argon Weekly Limit",
              "window": "weekly",
              "resetTime": "2026-11-12T18:23:27Z",
              "remainingFraction": 0.45134985
            }
          ],
          "displayName": "Gemini 4 Argon"
        }
      ]
    }
    """

    // MARK: - parseLogin

    func testParseLoginDecodesGoKeyringBase64Payload() {
        let json = """
        {
          "token": {
            "access_token": "ya29.fake-token",
            "refresh_token": "1//fake-refresh",
            "expiry": "2026-10-21T18:10:00.518907Z"
          },
          "auth_method": "consumer",
          "id_token_email": "alan@example.com",
          "user_tier": "g1-pro-tier"
        }
        """
        let encoded = "go-keyring-base64:" + Data(json.utf8).base64EncodedString() + "\n"

        let login = GeminiUsageAPI.parseLogin(Data(encoded.utf8))

        XCTAssertEqual(login, GeminiUsageAPI.Login(
            accessToken: "ya29.fake-token",
            refreshToken: "1//fake-refresh",
            expiresAt: ISO8601DateFormatter().date(from: "2026-10-21T18:10:00Z"),
            authMethod: "consumer",
            email: "alan@example.com",
            userTier: "g1-pro-tier"
        ))
    }

    func testParseLoginDecodesGoKeyringHexPayload() {
        let json = #"{"token":{"access_token":"ya29.hex"}}"#
        let hex = Data(json.utf8).map { String(format: "%02x", $0) }.joined()
        let encoded = "go-keyring-encoded:" + hex

        let login = GeminiUsageAPI.parseLogin(Data(encoded.utf8))

        XCTAssertEqual(login?.accessToken, "ya29.hex")
    }

    func testParseLoginReadsRawJSONPayload() {
        let json = #"{"token":{"access_token":"ya29.raw"},"id_token_email":"user@example.com"}"#

        let login = GeminiUsageAPI.parseLogin(Data(json.utf8))

        XCTAssertEqual(login?.accessToken, "ya29.raw")
        XCTAssertEqual(login?.email, "user@example.com")
    }

    func testParseLoginWithoutTokenReturnsNil() {
        let data = Data(#"{"auth_method":"consumer"}"#.utf8)

        XCTAssertNil(GeminiUsageAPI.parseLogin(data))
    }

    func testParseLoginWithEmptyTokensReturnsNil() {
        let data = Data(#"{"token":{"access_token":"","refresh_token":""}}"#.utf8)

        XCTAssertNil(GeminiUsageAPI.parseLogin(data))
    }

    // MARK: - usageResult

    func testUsageResultMapsPrimaryWeeklyArgonAndThirdPartyBuckets() {
        let result = GeminiUsageAPI.usageResult(
            from: Data(quotaBody.utf8),
            httpStatus: 200,
            email: "alan@example.com",
            planName: "Google AI Pro",
            timeZone: eastern
        )

        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(result["percentage"] as? Int, 3)
        XCTAssertEqual(result["resetTime"] as? String, "Resets Nov 5, 2026 11:08 PM")
        XCTAssertEqual(result["weeklyPercentage"] as? Int, 2)
        XCTAssertEqual(result["weeklyResetTime"] as? String, "Resets Nov 11, 2026 3:23 PM")
        XCTAssertEqual(result["sonnetWeeklyPercentage"] as? Int, 55)
        XCTAssertEqual(result["sonnetWeeklyLabel"] as? String, "Weekly (Argon)")
        XCTAssertEqual(result["sonnetWeeklyResetTime"] as? String, "Resets Nov 12, 2026 1:23 PM")
        XCTAssertEqual(result["designDailyPercentage"] as? Int, 0)
        XCTAssertEqual(result["designDailyLabel"] as? String, "Session (Claude & GPT)")
        XCTAssertEqual(result["designDailyResetTime"] as? String, "Resets Nov 6, 2026 2:28 AM")
        XCTAssertEqual(result["designWeeklyPercentage"] as? Int, 0)
        XCTAssertEqual(result["designWeeklyLabel"] as? String, "Weekly (Claude & GPT)")
        XCTAssertEqual(result["designWeeklyResetTime"] as? String, "Resets Nov 12, 2026 9:28 PM")
        XCTAssertEqual(result["email"] as? String, "alan@example.com")
        XCTAssertEqual(result["planName"] as? String, "Google AI Pro")
    }

    func testUsageResultTreatsOmittedRemainingFractionAsHundredPercentUsed() {
        let exhaustedBody = """
        {
          "groups": [
            {
              "displayName": "Gemini Models",
              "buckets": [
                {"bucketId": "gemini-5h", "window": "5h", "resetTime": "2026-11-06T04:08:12Z"}
              ]
            }
          ]
        }
        """

        let result = GeminiUsageAPI.usageResult(
            from: Data(exhaustedBody.utf8),
            httpStatus: 200,
            email: nil,
            planName: nil,
            timeZone: eastern
        )

        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(result["percentage"] as? Int, 100)
    }

    func testUsageResultOn401ReportsExpiredLogin() {
        let result = GeminiUsageAPI.usageResult(from: Data(), httpStatus: 401, email: nil, planName: nil)

        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertEqual(result["error"] as? String, GeminiUsageAPI.expiredLoginMessage)
    }

    func testUsageResultOnServerErrorReportsStatus() {
        let result = GeminiUsageAPI.usageResult(from: Data("busy".utf8), httpStatus: 503, email: nil, planName: nil)

        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertEqual(result["error"] as? String, "Gemini usage request failed (HTTP 503). Will retry automatically.")
    }

    func testUsageResultWithoutBucketsFails() {
        let result = GeminiUsageAPI.usageResult(from: Data(#"{"groups": []}"#.utf8), httpStatus: 200, email: nil, planName: nil)

        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertNotNil(result["error"] as? String)
    }

    // MARK: - parsePlanName

    func testParsePlanNamePrefersPaidTierName() {
        let body = """
        {
          "currentTier": {"id": "free-tier", "name": "Antigravity"},
          "paidTier": {"id": "g1-pro-tier", "name": "Google AI Pro"}
        }
        """

        let plan = GeminiUsageAPI.parsePlanName(from: Data(body.utf8))

        XCTAssertEqual(plan, "Google AI Pro")
    }

    func testParsePlanNameFallsBackToCurrentTierAndFormatsFreeTier() {
        let body = """
        {
          "currentTier": {"id": "free-tier", "name": "Antigravity"}
        }
        """

        let plan = GeminiUsageAPI.parsePlanName(from: Data(body.utf8))

        XCTAssertEqual(plan, "Free")
    }

    func testParsePlanNameUsesFallbackTierWhenResponseIsEmpty() {
        let plan = GeminiUsageAPI.parsePlanName(from: Data(), fallbackTier: "g1-ultra-tier")

        XCTAssertEqual(plan, "Google AI Ultra")
    }

    // MARK: - fetchResult

    func testFetchResultWithExpiredLoginSkipsTheRequest() async {
        let login = GeminiUsageAPI.Login(
            accessToken: "ya29.expired",
            expiresAt: Date(timeIntervalSince1970: 100),
            authMethod: "consumer",
            email: nil,
            userTier: nil
        )

        let result = await GeminiUsageAPI.fetchResult(login: login, now: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertEqual(result["error"] as? String, GeminiUsageAPI.expiredLoginMessage)
    }

    // MARK: - Token Refresh & Auto-Renewal

    func testRefreshLoginReturnsNilWhenRefreshTokenIsMissing() {
        let login = GeminiUsageAPI.Login(accessToken: "ya29.initial")
        let refreshed = GeminiUsageAPI.refreshLogin(login)

        XCTAssertNil(refreshed)
    }

    func testFindCLIExecutableReturnsValidURLWhenPresent() {
        let url = GeminiUsageAPI.findCLIExecutable()
        if let url {
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: url.path))
        }
    }

    func testFetchResultAutoRefreshesWhenExpiringSoon() async {
        let session = makeMockSession()
        let now = Date(timeIntervalSince1970: 1_000_000)

        GeminiUsageAPI.onRefreshLogin = { login in
            GeminiUsageAPI.Login(
                accessToken: "ya29.refreshed-token",
                refreshToken: login.refreshToken,
                expiresAt: now.addingTimeInterval(3600),
                authMethod: login.authMethod,
                email: login.email,
                userTier: login.userTier
            )
        }

        MockURLProtocol.requestHandler = { [weak self] request in
            guard let self else { throw URLError(.cancelled) }
            if request.url == GeminiUsageAPI.quotaURL {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ya29.refreshed-token")
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(self.quotaBody.utf8))
            }
            if request.url == GeminiUsageAPI.loadCodeAssistURL {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = #"{"paidTier": {"name": "Google AI Pro"}}"#
                return (response, Data(body.utf8))
            }
            throw URLError(.badURL)
        }

        let expiringLogin = GeminiUsageAPI.Login(
            accessToken: "ya29.expired-token",
            refreshToken: "rt-valid",
            expiresAt: now.addingTimeInterval(-10), // expired 10 seconds ago
            authMethod: "consumer",
            email: "alan@example.com",
            userTier: "g1-pro-tier"
        )

        let result = await GeminiUsageAPI.fetchResult(login: expiringLogin, now: now, session: session)

        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(result["percentage"] as? Int, 3)
        XCTAssertEqual(result["planName"] as? String, "Google AI Pro")
    }

    func testFetchResultAutoRefreshesOn401Unauthorized() async {
        let session = makeMockSession()
        let now = Date(timeIntervalSince1970: 1_000_000)
        var quotaCallCount = 0

        GeminiUsageAPI.onRefreshLogin = { login in
            GeminiUsageAPI.Login(
                accessToken: "ya29.second-token",
                refreshToken: login.refreshToken,
                expiresAt: now.addingTimeInterval(3600),
                authMethod: login.authMethod,
                email: login.email,
                userTier: login.userTier
            )
        }

        MockURLProtocol.requestHandler = { [weak self] request in
            guard let self else { throw URLError(.cancelled) }
            if request.url == GeminiUsageAPI.quotaURL {
                quotaCallCount += 1
                if quotaCallCount == 1 {
                    let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                    return (response, Data(#"{"error": "unauthorized"}"#.utf8))
                } else {
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ya29.second-token")
                    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (response, Data(self.quotaBody.utf8))
                }
            }
            if request.url == GeminiUsageAPI.loadCodeAssistURL {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = #"{"paidTier": {"name": "Google AI Pro"}}"#
                return (response, Data(body.utf8))
            }
            throw URLError(.badURL)
        }

        let login = GeminiUsageAPI.Login(
            accessToken: "ya29.first-token",
            refreshToken: "rt-valid",
            expiresAt: now.addingTimeInterval(3000), // looks valid on clock
            authMethod: "consumer",
            email: "alan@example.com",
            userTier: "g1-pro-tier"
        )

        let result = await GeminiUsageAPI.fetchResult(login: login, now: now, session: session)

        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(quotaCallCount, 2)
    }

    func testFetchResultFallsBackWhenDailyEndpointFails() async {
        let session = makeMockSession()
        let now = Date(timeIntervalSince1970: 1_000_000)

        MockURLProtocol.requestHandler = { [weak self] request in
            guard let self else { throw URLError(.cancelled) }
            if request.url == GeminiUsageAPI.quotaURL {
                let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"error": "unavailable"}"#.utf8))
            }
            if request.url == GeminiUsageAPI.fallbackQuotaURL {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(self.quotaBody.utf8))
            }
            if request.url == GeminiUsageAPI.loadCodeAssistURL || request.url == GeminiUsageAPI.fallbackLoadCodeAssistURL {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = #"{"paidTier": {"name": "Google AI Pro"}}"#
                return (response, Data(body.utf8))
            }
            throw URLError(.badURL)
        }

        let login = GeminiUsageAPI.Login(
            accessToken: "ya29.valid-token",
            refreshToken: "rt-valid",
            expiresAt: now.addingTimeInterval(3000),
            authMethod: "consumer",
            email: "alan@example.com",
            userTier: "g1-pro-tier"
        )

        let result = await GeminiUsageAPI.fetchResult(login: login, now: now, session: session)
        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(result["percentage"] as? Int, 3)
    }

    private func makeMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        GeminiUsageAPI.onRefreshLogin = nil
        super.tearDown()
    }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            XCTFail("No handler provided for request")
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
