import Foundation

// Reads Gemini usage the same way `agy -p /usage` does: it reads the OAuth token
// that the Gemini / Antigravity CLI saves in the macOS Keychain under service "gemini"
// and posts to Cloud Code's retrieveUserQuotaSummary and loadCodeAssist endpoints.
// When the access token expires or nears expiration, it automatically invokes the CLI
// in the background to renew the token and reloads the fresh credentials from Keychain.
enum GeminiUsageAPI {
    static let quotaURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")!
    static let loadCodeAssistURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!
    static let keychainService = "gemini"
    static let proactiveRefreshWindow: TimeInterval = 300 // 5 minutes
    static let requestTimeout: TimeInterval = 20
    static let expiredLoginMessage = "Gemini CLI's login has expired. Run gemini in Terminal to renew it."
    static let userAgent = "antigravity/cli/1.5.1 (aidev_client; os_type=darwin; arch=arm64; cl=1014269460; auth_method=consumer)"

    nonisolated(unsafe) static var onRefreshLogin: ((Login) -> Login?)? = nil

    private static let keyringBase64Prefix = "go-keyring-base64:"
    private static let keyringHexPrefix = "go-keyring-encoded:"

    struct Login: Equatable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
        let authMethod: String?
        let email: String?
        let userTier: String?

        init(
            accessToken: String,
            refreshToken: String? = nil,
            expiresAt: Date? = nil,
            authMethod: String? = nil,
            email: String? = nil,
            userTier: String? = nil
        ) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresAt = expiresAt
            self.authMethod = authMethod
            self.email = email
            self.userTier = userTier
        }

        func isExpiredOrExpiringSoon(now: Date = Date(), window: TimeInterval = proactiveRefreshWindow) -> Bool {
            guard let expiresAt else { return false }
            return expiresAt.timeIntervalSince(now) <= window
        }
    }

    // Reads through /usr/bin/security so the item's ACL (written by go-keyring via
    // /usr/bin/security) grants access without prompting on ad hoc signed updates.
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
        guard let decoded = decodeKeychainPayload(data),
              let root = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any],
              let token = root["token"] as? [String: Any] else {
            return nil
        }
        let accessToken = (token["access_token"] as? String) ?? ""
        guard !accessToken.isEmpty else { return nil }
        let refreshToken = nonEmpty(token["refresh_token"] as? String)
        let expiresAt = (token["expiry"] as? String).flatMap(parseISODate)
        return Login(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            authMethod: nonEmpty(root["auth_method"] as? String),
            email: nonEmpty(root["id_token_email"] as? String),
            userTier: nonEmpty(root["user_tier"] as? String)
        )
    }

    static func refreshLogin(_ login: Login) -> Login? {
        if let customHandler = onRefreshLogin {
            return customHandler(login)
        }
        guard let refreshToken = login.refreshToken, !refreshToken.isEmpty else {
            return nil
        }
        guard let cliURL = findCLIExecutable() else { return nil }
        let process = Process()
        process.executableURL = cliURL
        process.arguments = ["-p", "/usage"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        guard let refreshed = readLogin() else { return nil }
        return refreshed
    }

    static func findCLIExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/agy").path,
            home.appendingPathComponent(".local/bin/gemini").path,
            "/usr/local/bin/agy",
            "/usr/local/bin/gemini",
            "/opt/homebrew/bin/agy",
            "/opt/homebrew/bin/gemini"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which agy 2>/dev/null || which gemini 2>/dev/null"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let resolved = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolved.isEmpty, FileManager.default.isExecutableFile(atPath: resolved) else { return nil }
        return URL(fileURLWithPath: resolved)
    }

    static func decodeKeychainPayload(_ data: Data) -> Data? {
        let raw = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if raw.hasPrefix(keyringBase64Prefix) {
            let encoded = String(raw.dropFirst(keyringBase64Prefix.count))
            return Data(base64Encoded: encoded)
        }
        if raw.hasPrefix(keyringHexPrefix) {
            let hex = String(raw.dropFirst(keyringHexPrefix.count))
            return decodeHex(hex)
        }
        return Data(raw.utf8)
    }

    static func fetchResult(
        login: Login,
        now: Date = Date(),
        session: URLSession = .shared
    ) async -> [String: Any] {
        var currentLogin = login

        if currentLogin.isExpiredOrExpiringSoon(now: now) {
            if let refreshed = await Task.detached(operation: { refreshLogin(currentLogin) }).value {
                currentLogin = refreshed
            }
        }

        if let expiresAt = currentLogin.expiresAt, expiresAt <= now {
            return result(["success": false, "error": expiredLoginMessage], debug: ["source": "geminiLogin", "loginExpired": true])
        }

        do {
            var (data, httpStatus) = try await postJSON(url: quotaURL, body: Data("{}".utf8), accessToken: currentLogin.accessToken, session: session)

            if httpStatus == 401, let refreshed = await Task.detached(operation: { refreshLogin(currentLogin) }).value {
                currentLogin = refreshed
                let retryResult = try await postJSON(url: quotaURL, body: Data("{}".utf8), accessToken: currentLogin.accessToken, session: session)
                data = retryResult.0
                httpStatus = retryResult.1
            }

            let planName = await fetchPlanName(accessToken: currentLogin.accessToken, fallbackTier: currentLogin.userTier, httpStatus: httpStatus, session: session)
            return usageResult(from: data, httpStatus: httpStatus, email: currentLogin.email, planName: planName)
        } catch {
            return result(
                ["success": false, "error": "Could not reach Google Cloud Code: \(error.localizedDescription)"],
                debug: ["source": "geminiLogin"]
            )
        }
    }

    static func usageResult(
        from data: Data,
        httpStatus: Int,
        email: String?,
        planName: String?,
        timeZone: TimeZone = .current
    ) -> [String: Any] {
        let debug: [String: Any] = [
            "source": "geminiLogin",
            "httpStatus": httpStatus,
            "body": String(decoding: data.prefix(4000), as: UTF8.self)
        ]
        guard httpStatus != 401 else {
            return result(["success": false, "error": expiredLoginMessage], debug: debug)
        }
        guard httpStatus == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return result(
                ["success": false, "error": "Gemini usage request failed (HTTP \(httpStatus)). Will retry automatically."],
                debug: debug
            )
        }

        let groups = json["groups"] as? [[String: Any]] ?? []
        let allBuckets = groups.flatMap { $0["buckets"] as? [[String: Any]] ?? [] }
        let geminiGroup = groups.first { ($0["displayName"] as? String) == "Gemini Models" }
        let geminiBuckets = geminiGroup?["buckets"] as? [[String: Any]] ?? []

        let session = allBuckets.first { ($0["bucketId"] as? String) == "gemini-5h" }
            ?? geminiBuckets.first { ($0["window"] as? String) == "5h" }
        let weekly = allBuckets.first { ($0["bucketId"] as? String) == "gemini-weekly" }
            ?? geminiBuckets.first { ($0["window"] as? String) == "weekly" }
        let scoped = scopedWeeklyBuckets(from: groups)
        let firstScoped = scoped.first
        let secondScoped = scoped.dropFirst().first

        // Find the 3p (Claude & GPT) 5-hour session bucket if present
        let thirdPartyGroup = groups.first {
            let name = ($0["displayName"] as? String ?? "").lowercased()
            return name.contains("claude") || name.contains("gpt") || name.contains("3p")
        }
        let thirdPartyBuckets = thirdPartyGroup?["buckets"] as? [[String: Any]] ?? []
        let thirdPartySession = thirdPartyBuckets.first {
            ($0["bucketId"] as? String)?.contains("5h") == true || ($0["window"] as? String) == "5h"
        }

        let hasUsage = session != nil || weekly != nil || firstScoped != nil

        let fields: [String: Any] = [
            "success": hasUsage,
            "error": (hasUsage ? nil : "No Gemini usage limits in the response. See body in debug.") as Any,
            "percentage": usedPercentage(for: session) as Any,
            "resetTime": resetTime(for: session, timeZone: timeZone) as Any,
            "weeklyPercentage": usedPercentage(for: weekly) as Any,
            "weeklyResetTime": resetTime(for: weekly, timeZone: timeZone) as Any,
            "sonnetWeeklyPercentage": usedPercentage(for: firstScoped?.bucket) as Any,
            "sonnetWeeklyResetTime": resetTime(for: firstScoped?.bucket, timeZone: timeZone) as Any,
            "sonnetWeeklyLabel": firstScoped?.label as Any,
            "designDailyPercentage": usedPercentage(for: thirdPartySession) as Any,
            "designDailyResetTime": resetTime(for: thirdPartySession, timeZone: timeZone) as Any,
            "designDailyLabel": (thirdPartySession != nil ? "Session (Claude & GPT)" : nil) as Any,
            "designWeeklyPercentage": usedPercentage(for: secondScoped?.bucket) as Any,
            "designWeeklyResetTime": resetTime(for: secondScoped?.bucket, timeZone: timeZone) as Any,
            "designWeeklyLabel": secondScoped?.label as Any,
            "email": email as Any,
            "planName": planName as Any
        ]
        return result(fields, debug: debug)
    }

    static func parsePlanName(from data: Data, fallbackTier: String? = nil) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return formatTierName(fallbackTier)
        }
        if let paidTier = json["paidTier"] as? [String: Any],
           let paidName = nonEmpty(paidTier["name"] as? String ?? paidTier["id"] as? String) {
            return formatTierName(paidName)
        }
        if let currentTier = json["currentTier"] as? [String: Any],
           let tierID = nonEmpty(currentTier["id"] as? String ?? currentTier["name"] as? String) {
            return formatTierName(tierID)
        }
        return formatTierName(fallbackTier)
    }

    // MARK: - Private Helpers

    private static func fetchPlanName(accessToken: String, fallbackTier: String?, httpStatus: Int, session: URLSession) async -> String? {
        guard httpStatus == 200 else { return formatTierName(fallbackTier) }
        let body = Data(#"{"metadata":{"ideType":"ANTIGRAVITY"}}"#.utf8)
        guard let (data, status) = try? await postJSON(url: loadCodeAssistURL, body: body, accessToken: accessToken, session: session),
              status == 200 else {
            return formatTierName(fallbackTier)
        }
        return parsePlanName(from: data, fallbackTier: fallbackTier)
    }

    private static func postJSON(url: URL, body: Data, accessToken: String, session: URLSession) async throws -> (Data, Int) {
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, httpStatus)
    }

    private static func scopedWeeklyBuckets(from groups: [[String: Any]]) -> [(label: String, bucket: [String: Any])] {
        let nonPrimaryGroups = groups.filter { ($0["displayName"] as? String) != "Gemini Models" }
        let sortedGroups = nonPrimaryGroups.sorted { lhs, rhs in
            scopedPriority(for: lhs["displayName"] as? String) < scopedPriority(for: rhs["displayName"] as? String)
        }
        return sortedGroups.compactMap { group in
            let buckets = group["buckets"] as? [[String: Any]] ?? []
            guard let weeklyBucket = buckets.first(where: { ($0["window"] as? String) == "weekly" }) ?? buckets.first else {
                return nil
            }
            let label = scopedLabel(for: group["displayName"] as? String, bucket: weeklyBucket)
            return (label: label, bucket: weeklyBucket)
        }
    }

    private static func scopedPriority(for groupName: String?) -> Int {
        let lower = (groupName ?? "").lowercased()
        if lower.contains("argon") { return 0 }
        if lower.contains("claude") || lower.contains("gpt") { return 1 }
        return 2
    }

    private static func scopedLabel(for groupName: String?, bucket: [String: Any]) -> String {
        let name = groupName ?? (bucket["displayName"] as? String) ?? "Models"
        let lower = name.lowercased()
        if lower.contains("argon") { return "Weekly (Argon)" }
        if lower.contains("claude") && lower.contains("gpt") { return "Weekly (Claude & GPT)" }
        return "Weekly (\(name))"
    }

    private static func usedPercentage(for bucket: [String: Any]?) -> Int? {
        guard let bucket else { return nil }
        // Protobuf JSON omits remainingFraction when it reaches 0 (100% used).
        let remaining = (bucket["remainingFraction"] as? NSNumber)?.doubleValue ?? 0.0
        let used = (1.0 - remaining) * 100.0
        return min(100, max(0, Int(used.rounded())))
    }

    private static func resetTime(for bucket: [String: Any]?, timeZone: TimeZone) -> String? {
        guard let isoDate = bucket?["resetTime"] as? String else { return nil }
        return ClaudeCodeUsageAPI.resetText(fromISODate: isoDate, timeZone: timeZone)
    }

    private static func formatTierName(_ rawTier: String?) -> String? {
        guard let tier = nonEmpty(rawTier) else { return nil }
        let lower = tier.lowercased()
        if lower == "free-tier" || lower == "free" { return "Free" }
        if lower == "g1-pro-tier" { return "Google AI Pro" }
        if lower == "g1-ultra-tier" { return "Google AI Ultra" }
        if lower == "standard-tier" { return "Standard" }
        return tier
    }

    private static func parseISODate(_ isoDate: String) -> Date? {
        let withoutFraction = isoDate.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: withoutFraction)
    }

    private static func decodeHex(_ hex: String) -> Data? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        let chars = Array(hex)
        let bytes = stride(from: 0, to: chars.count, by: 2).compactMap { index -> UInt8? in
            UInt8(String(chars[index...index + 1]), radix: 16)
        }
        guard bytes.count == chars.count / 2 else { return nil }
        return Data(bytes)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func result(_ fields: [String: Any], debug: [String: Any]) -> [String: Any] {
        let debugData = (try? JSONSerialization.data(withJSONObject: debug, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return fields.merging(["debug": String(decoding: debugData, as: UTF8.self)]) { _, new in new }
    }
}
