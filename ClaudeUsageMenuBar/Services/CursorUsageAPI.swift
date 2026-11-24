import Foundation

// Reads Cursor usage from cursor.com instead of the dashboard page. The page's own
// usage request can sit until the refresh times out, while GET /api/usage-summary
// returns the same pools in one response. The session is the Cursor CLI access
// token already in the login keychain, sent as the WorkOS session cookie.
enum CursorUsageAPI {
    static let usageURL = URL(string: "https://cursor.com/api/usage-summary")!
    static let keychainService = "cursor-access-token"
    static let keychainAccount = "cursor-user"
    static let requestTimeout: TimeInterval = 20
    static let expiredLoginMessage = "Cursor's login has expired. Open Cursor to sign in again."

    struct Login: Equatable {
        let accessToken: String
        let expiresAt: Date?
    }

    // The security tool is on the item's access list, so this does not prompt.
    // A direct keychain read prompts again after each ad hoc rebuild.
    static func readLogin() -> Login? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-a", keychainAccount, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, jwtPayload(token) != nil else { return nil }
        return Login(accessToken: token, expiresAt: expiry(of: token))
    }

    static func fetchResult(login: Login, now: Date = Date(), session: URLSession = .shared) async -> [String: Any] {
        if let expiresAt = login.expiresAt, expiresAt <= now {
            return result(["success": false, "error": expiredLoginMessage], debug: ["source": "cursorLogin", "loginExpired": true])
        }
        guard let cookie = sessionCookie(for: login.accessToken) else {
            return result(["success": false, "error": expiredLoginMessage], debug: ["source": "cursorLogin", "sessionCookie": false])
        }

        var request = URLRequest(url: usageURL, timeoutInterval: requestTimeout)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")

        do {
            let (data, response) = try await session.data(for: request)
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            return usageResult(from: data, httpStatus: httpStatus)
        } catch {
            return result(
                ["success": false, "error": "Could not reach Cursor: \(error.localizedDescription)"],
                debug: ["source": "cursorLogin"]
            )
        }
    }

    // Other Models is apiPercentUsed, Cursor Models is autoPercentUsed, and the
    // included total is totalPercentUsed. On-demand is the user's own spend.
    static func usageResult(from data: Data, httpStatus: Int, timeZone: TimeZone = .current) -> [String: Any] {
        let debug: [String: Any] = [
            "source": "cursorLogin",
            "httpStatus": httpStatus,
            "body": String(decoding: data.prefix(4000), as: UTF8.self)
        ]
        guard httpStatus != 401, httpStatus != 403 else {
            return result(["success": false, "error": expiredLoginMessage], debug: debug)
        }
        guard httpStatus == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return result(
                ["success": false, "error": "Cursor usage request failed (HTTP \(httpStatus)). Will retry automatically."],
                debug: debug
            )
        }

        let individual = json["individualUsage"] as? [String: Any]
        let plan = individual?["plan"] as? [String: Any]
        let reset = (json["billingCycleEnd"] as? String).flatMap { ClaudeCodeUsageAPI.resetText(fromISODate: $0, timeZone: timeZone) }
        var percentage = roundedPercent(plan?["totalPercentUsed"])
        if percentage == nil {
            let used = number(plan?["used"])
            let limit = number(plan?["limit"])
            if let used, let limit, limit > 0 { percentage = Int((used / limit * 100).rounded()) }
        }
        let otherModels = roundedPercent(plan?["apiPercentUsed"])
        let cursorModels = roundedPercent(plan?["autoPercentUsed"])
        let onDemand = number((individual?["onDemand"] as? [String: Any])?["used"]).map { $0 / 100 }
        let hasUsage = percentage != nil || otherModels != nil || cursorModels != nil || onDemand != nil

        let fields: [String: Any] = [
            "success": hasUsage,
            "error": (hasUsage ? nil : "No Cursor usage in the response. See body in debug.") as Any,
            "percentage": percentage as Any,
            "resetTime": reset as Any,
            "weeklyPercentage": otherModels as Any,
            "weeklyResetTime": reset as Any,
            "sonnetWeeklyPercentage": cursorModels as Any,
            "sonnetWeeklyResetTime": reset as Any,
            "sonnetWeeklyLabel": (cursorModels != nil ? "Cursor Models" : nil) as Any,
            "planName": planDisplayName(json["membershipType"] as? String) as Any,
            "onDemandUsed": onDemand as Any
        ]
        return result(fields, debug: debug)
    }

    // WorkOS expects userId::jwt, with the user id taken from the token subject.
    static func sessionCookie(for accessToken: String) -> String? {
        guard let subject = jwtPayload(accessToken)?["sub"] as? String else { return nil }
        let userID = subject.split(separator: "|").last.map(String.init) ?? subject
        guard !userID.isEmpty else { return nil }
        let raw = "\(userID)::\(accessToken)"
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encoded = raw.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return "WorkosCursorSessionToken=\(encoded)"
    }

    static func planDisplayName(_ membershipType: String?) -> String? {
        guard let membershipType, !membershipType.isEmpty else { return nil }
        return membershipType.split(separator: "_").map { part in
            guard let first = part.first else { return "" }
            return first.uppercased() + part.dropFirst()
        }.joined(separator: " ")
    }

    private static func roundedPercent(_ value: Any?) -> Int? {
        guard let number = number(value), number.isFinite else { return nil }
        return Int(number.rounded())
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    private static func expiry(of token: String) -> Date? {
        guard let exp = jwtPayload(token)?["exp"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: exp.doubleValue)
    }

    static func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json
    }

    private static func result(_ fields: [String: Any], debug: [String: Any]) -> [String: Any] {
        let debugData = (try? JSONSerialization.data(withJSONObject: debug, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return fields.merging(["debug": String(decoding: debugData, as: UTF8.self)]) { _, new in new }
    }
}
