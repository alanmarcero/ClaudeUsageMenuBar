import Foundation

// Reads Claude usage the same way Claude Code's /usage does: it sends the OAuth login
// that Claude Code saves in the keychain to Anthropic's usage endpoint. This skips the
// claude.ai web login, which an SSO device check can block in an embedded web view.
// The app only reads the login. It never refreshes it, because a refresh replaces the
// token and signs Claude Code out.
enum ClaudeCodeUsageAPI {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let betaHeader = "oauth-2025-04-20"
    static let keychainService = "Claude Code-credentials"
    static let requestTimeout: TimeInterval = 20
    static let expiredLoginMessage = "Claude Code's login has expired. Open Claude Code to renew it."

    struct Login: Equatable {
        let accessToken: String
        let expiresAt: Date?
        let subscriptionType: String?
    }

    // Reads through the security tool, not SecItemCopyMatching. Claude Code writes the
    // item with that tool, so the item's access list already trusts it and no prompt
    // shows. A direct read prompts again after each update of this ad hoc signed app.
    static func readLogin() -> Login? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return parseLogin(data)
    }

    static func parseLogin(_ data: Data) -> Login? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              !accessToken.isEmpty else {
            return nil
        }
        let expiresAt = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return Login(accessToken: accessToken, expiresAt: expiresAt, subscriptionType: oauth["subscriptionType"] as? String)
    }

    // Returns the same dictionary shape as the page scraping scripts, so UsageService
    // handles both sources the same way.
    static func fetchResult(login: Login, now: Date = Date(), session: URLSession = .shared) async -> [String: Any] {
        if let expiresAt = login.expiresAt, expiresAt <= now {
            return result(["success": false, "error": expiredLoginMessage], debug: ["source": "claudeCodeLogin", "loginExpired": true])
        }

        var request = URLRequest(url: usageURL, timeoutInterval: requestTimeout)
        request.setValue("Bearer \(login.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")

        do {
            let (data, response) = try await session.data(for: request)
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            return usageResult(from: data, httpStatus: httpStatus, planName: login.subscriptionType?.capitalized)
        } catch {
            return result(
                ["success": false, "error": "Could not reach Anthropic: \(error.localizedDescription)"],
                debug: ["source": "claudeCodeLogin"]
            )
        }
    }

    // Maps the response's "limits" rows: "session" is the 5-hour limit, "weekly_all" the
    // weekly limit, and each "weekly_scoped" row a per-model weekly limit (e.g. Fable).
    static func usageResult(from data: Data, httpStatus: Int, planName: String?, timeZone: TimeZone = .current) -> [String: Any] {
        let debug: [String: Any] = [
            "source": "claudeCodeLogin",
            "httpStatus": httpStatus,
            "body": String(decoding: data.prefix(4000), as: UTF8.self)
        ]
        guard httpStatus != 401 else {
            return result(["success": false, "error": expiredLoginMessage], debug: debug)
        }
        guard httpStatus == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return result(
                ["success": false, "error": "Claude usage request failed (HTTP \(httpStatus)). Will retry automatically."],
                debug: debug
            )
        }

        let limits = json["limits"] as? [[String: Any]] ?? []
        let session = limits.first { $0["kind"] as? String == "session" }
        let weekly = limits.first { $0["kind"] as? String == "weekly_all" }
        let scoped = limits.filter { $0["kind"] as? String == "weekly_scoped" }
        let firstScoped = scoped.first
        let secondScoped = scoped.dropFirst().first
        let hasUsage = session != nil || weekly != nil

        let percent = { (limit: [String: Any]?) in (limit?["percent"] as? Double).map { Int($0.rounded()) } }
        let reset = { (limit: [String: Any]?) in
            (limit?["resets_at"] as? String).flatMap { resetText(fromISODate: $0, timeZone: timeZone) }
        }
        let scopeName = { (limit: [String: Any]?) -> String? in
            let scope = limit?["scope"] as? [String: Any]
            let model = scope?["model"] as? [String: Any]
            let surface = scope?["surface"] as? [String: Any]
            return model?["display_name"] as? String ?? surface?["display_name"] as? String ?? scope?["surface"] as? String
        }

        let fields: [String: Any] = [
            "success": hasUsage,
            "error": (hasUsage ? nil : "No Claude usage limits in the response. See body in debug.") as Any,
            "percentage": percent(session) as Any,
            "resetTime": reset(session) as Any,
            "weeklyPercentage": percent(weekly) as Any,
            "weeklyResetTime": reset(weekly) as Any,
            "sonnetWeeklyPercentage": percent(firstScoped) as Any,
            "sonnetWeeklyResetTime": reset(firstScoped) as Any,
            "sonnetWeeklyLabel": scopeName(firstScoped) as Any,
            "designWeeklyPercentage": percent(secondScoped) as Any,
            "designWeeklyResetTime": reset(secondScoped) as Any,
            "designWeeklyLabel": scopeName(secondScoped) as Any,
            "planName": planName as Any
        ]
        return result(fields, debug: debug)
    }

    // Formats an ISO 8601 reset time as an absolute string the countdown calculators
    // read, e.g. "Resets Oct 21, 2026 2:10 PM". The fraction is removed first because
    // ISO8601DateFormatter does not accept the API's 6 fraction digits. The time is
    // rounded to the nearest minute, because the API can send 06:59:59 for 07:00.
    static func resetText(fromISODate isoDate: String, timeZone: TimeZone) -> String? {
        let withoutFraction = isoDate.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        guard let date = ISO8601DateFormatter().date(from: withoutFraction) else { return nil }
        let roundedDate = Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, yyyy h:mm a"
        return "Resets \(formatter.string(from: roundedDate))"
    }

    private static func result(_ fields: [String: Any], debug: [String: Any]) -> [String: Any] {
        let debugData = (try? JSONSerialization.data(withJSONObject: debug, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return fields.merging(["debug": String(decoding: debugData, as: UTF8.self)]) { _, new in new }
    }
}
