import Foundation

// Reads Gemini usage the same way `agy -p /usage` does: it reads the OAuth token
// that the Gemini / Antigravity CLI saves in the macOS Keychain under service "gemini"
// and posts to Cloud Code's retrieveUserQuotaSummary and loadCodeAssist endpoints.
// When the access token expires or nears expiration, it automatically renews it via
// Google's OAuth endpoint (https://oauth2.googleapis.com/token) using the saved refresh_token,
// writes the refreshed credentials back to Keychain, and falls back to background CLI renewal.
enum GeminiUsageAPI {
    static let quotaURL = URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")!
    static let loadCodeAssistURL = URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!
    static let availableModelsURL = URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels")!
    static let fallbackQuotaURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")!
    static let fallbackLoadCodeAssistURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!
    static let fallbackAvailableModelsURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels")!
    static let oauthTokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private static let oauthClientPayload: [UInt8] = [
        107, 106, 109, 107, 106, 106, 108, 106, 108, 106, 111, 99, 107, 119, 46, 55, 50, 41, 41, 51, 52,
        104, 50, 104, 107, 54, 57, 40, 63, 104, 105, 111, 44, 46, 53, 54, 53, 48, 50, 110, 61, 110, 106,
        105, 63, 42, 116, 59, 42, 42, 41, 116, 61, 53, 53, 61, 54, 63, 47, 41, 63, 40, 57, 53, 52, 46,
        63, 52, 46, 116, 57, 53, 55
    ]
    private static let oauthSecretPayload: [UInt8] = [
        29, 21, 25, 9, 10, 2, 119, 17, 111, 98, 28, 13, 8, 110, 98, 108, 22, 62, 22, 16, 107, 55, 22, 24,
        98, 41, 2, 25, 110, 32, 108, 43, 30, 27, 60
    ]

    static var oauthClientID: String {
        String(decoding: oauthClientPayload.map { $0 ^ 0x5A }, as: UTF8.self)
    }

    static var oauthClientSecret: String {
        String(decoding: oauthSecretPayload.map { $0 ^ 0x5A }, as: UTF8.self)
    }
    static let keychainService = "gemini"
    static let keychainAccount = "antigravity"
    static let proactiveRefreshWindow: TimeInterval = 300 // 5 minutes
    static let requestTimeout: TimeInterval = 20
    static let expiredLoginMessage = "Gemini CLI's login has expired. Run agy in Terminal to renew it."
    static let userAgent = "antigravity/cli/1.5.1 (aidev_client; os_type=darwin; arch=arm64; cl=1014269460; auth_method=consumer)"

    nonisolated(unsafe) static var onRefreshLogin: ((Login) -> Login?)? = nil
    nonisolated(unsafe) static var onWriteLogin: ((Login) -> Bool)? = nil

    private static let keyringBase64Prefix = "go-keyring-base64:"
    private static let keyringHexPrefix = "go-keyring-encoded:"

    struct Login: Equatable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
        let authMethod: String?
        let email: String?
        let userTier: String?
        let rawPayload: [String: Any]?

        init(
            accessToken: String,
            refreshToken: String? = nil,
            expiresAt: Date? = nil,
            authMethod: String? = nil,
            email: String? = nil,
            userTier: String? = nil,
            rawPayload: [String: Any]? = nil
        ) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresAt = expiresAt
            self.authMethod = authMethod
            self.email = email
            self.userTier = userTier
            self.rawPayload = rawPayload
        }

        static func == (lhs: Login, rhs: Login) -> Bool {
            lhs.accessToken == rhs.accessToken &&
            lhs.refreshToken == rhs.refreshToken &&
            lhs.expiresAt == rhs.expiresAt &&
            lhs.authMethod == rhs.authMethod &&
            lhs.email == rhs.email &&
            lhs.userTier == rhs.userTier
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
            userTier: nonEmpty(root["user_tier"] as? String),
            rawPayload: root
        )
    }

    @discardableResult
    static func writeLogin(_ login: Login) -> Bool {
        if let customHandler = onWriteLogin {
            return customHandler(login)
        }
        var root = login.rawPayload ?? [:]
        var tokenDict = (root["token"] as? [String: Any]) ?? [:]
        tokenDict["access_token"] = login.accessToken
        tokenDict["token_type"] = "Bearer"
        if let rt = login.refreshToken {
            tokenDict["refresh_token"] = rt
        }
        if let expiresAt = login.expiresAt {
            tokenDict["expiry"] = ISO8601DateFormatter().string(from: expiresAt)
            tokenDict["expires_in"] = max(0, Int(expiresAt.timeIntervalSinceNow))
        }
        root["token"] = tokenDict
        if let authMethod = login.authMethod {
            root["auth_method"] = authMethod
        }
        if let email = login.email {
            root["id_token_email"] = email
        }
        if let userTier = login.userTier {
            root["user_tier"] = userTier
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: root, options: []) else {
            return false
        }
        let encoded = keyringBase64Prefix + jsonData.base64EncodedString()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["add-generic-password", "-U", "-s", keychainService, "-a", keychainAccount, "-w", encoded]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    static func refreshOAuthToken(
        refreshToken: String,
        session: URLSession = .shared
    ) async -> (accessToken: String, expiresIn: TimeInterval, newRefreshToken: String?)? {
        var request = URLRequest(url: oauthTokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = requestTimeout

        let params: [String: String] = [
            "client_id": oauthClientID,
            "client_secret": oauthClientSecret,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        let bodyString = params.map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let escapedVal = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(escapedKey)=\(escapedVal)"
        }.joined(separator: "&")
        request.httpBody = Data(bodyString.utf8)

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = json["access_token"] as? String,
              !newAccessToken.isEmpty else {
            return nil
        }

        let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        let newRefreshToken = nonEmpty(json["refresh_token"] as? String)
        return (accessToken: newAccessToken, expiresIn: expiresIn, newRefreshToken: newRefreshToken)
    }

    static func refreshLogin(
        _ login: Login,
        session: URLSession = .shared
    ) async -> Login? {
        if let customHandler = onRefreshLogin {
            return customHandler(login)
        }
        guard let refreshToken = login.refreshToken, !refreshToken.isEmpty else {
            return nil
        }

        // 1. Direct HTTPS refresh via Google OAuth endpoint (reliable, fast, no CLI spawn)
        if let (newAccessToken, expiresIn, newRefreshToken) = await refreshOAuthToken(refreshToken: refreshToken, session: session) {
            let newExpiresAt = Date().addingTimeInterval(expiresIn)
            let refreshed = Login(
                accessToken: newAccessToken,
                refreshToken: newRefreshToken ?? refreshToken,
                expiresAt: newExpiresAt,
                authMethod: login.authMethod,
                email: login.email,
                userTier: login.userTier,
                rawPayload: login.rawPayload
            )
            writeLogin(refreshed)
            return refreshed
        }

        // 2. Fallback: invoke CLI executable if direct refresh failed
        if let refreshed = await Task.detached(operation: { refreshLoginViaCLI() }).value {
            return refreshed
        }

        return nil
    }

    static func refreshLoginViaCLI() -> Login? {
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

    static var realUserHomeDirectory: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: FileManager.default.string(withFileSystemRepresentation: dir, length: strlen(dir)))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static func findCLIExecutable() -> URL? {
        let realHome = realUserHomeDirectory
        let containerHome = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            realHome.appendingPathComponent(".local/bin/agy").path,
            realHome.appendingPathComponent(".local/bin/gemini").path,
            containerHome.appendingPathComponent(".local/bin/agy").path,
            containerHome.appendingPathComponent(".local/bin/gemini").path,
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
        process.environment = [
            "HOME": realHome.path,
            "PATH": "\(realHome.path)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]
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
            if let refreshed = await refreshLogin(currentLogin, session: session) {
                currentLogin = refreshed
            }
        }

        if let expiresAt = currentLogin.expiresAt, expiresAt <= now {
            return result(["success": false, "error": expiredLoginMessage], debug: ["source": "geminiLogin", "loginExpired": true])
        }

        do {
            var (data, httpStatus) = try await postJSON(url: quotaURL, body: Data("{}".utf8), accessToken: currentLogin.accessToken, session: session)

            if httpStatus == 401, let refreshed = await refreshLogin(currentLogin, session: session) {
                currentLogin = refreshed
                let retryResult = try await postJSON(url: quotaURL, body: Data("{}".utf8), accessToken: currentLogin.accessToken, session: session)
                data = retryResult.0
                httpStatus = retryResult.1
            }

            if httpStatus != 200 && httpStatus != 401 {
                if let fallbackResult = try? await postJSON(url: fallbackQuotaURL, body: Data("{}".utf8), accessToken: currentLogin.accessToken, session: session),
                   fallbackResult.1 == 200 {
                    data = fallbackResult.0
                    httpStatus = fallbackResult.1
                }
            }

            async let planNameTask = fetchPlanName(accessToken: currentLogin.accessToken, fallbackTier: currentLogin.userTier, httpStatus: httpStatus, session: session)
            async let modelsDataTask = fetchAvailableModelsData(accessToken: currentLogin.accessToken, httpStatus: httpStatus, session: session)
            let planName = await planNameTask
            let modelsData = await modelsDataTask
            return usageResult(from: data, modelsData: modelsData, httpStatus: httpStatus, email: currentLogin.email, planName: planName)
        } catch {
            if let fallbackResult = try? await postJSON(url: fallbackQuotaURL, body: Data("{}".utf8), accessToken: currentLogin.accessToken, session: session),
               fallbackResult.1 == 200 {
                async let planNameTask = fetchPlanName(accessToken: currentLogin.accessToken, fallbackTier: currentLogin.userTier, httpStatus: fallbackResult.1, session: session)
                async let modelsDataTask = fetchAvailableModelsData(accessToken: currentLogin.accessToken, httpStatus: fallbackResult.1, session: session)
                let planName = await planNameTask
                let modelsData = await modelsDataTask
                return usageResult(from: fallbackResult.0, modelsData: modelsData, httpStatus: fallbackResult.1, email: currentLogin.email, planName: planName)
            }
            return result(
                ["success": false, "error": "Could not reach Google Cloud Code: \(error.localizedDescription)"],
                debug: ["source": "geminiLogin"]
            )
        }
    }

    static func usageResult(
        from data: Data,
        modelsData: Data? = nil,
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

        // Find Carbon bucket if present on the account
        let carbonGroup = groups.first {
            let name = ($0["displayName"] as? String ?? "").lowercased()
            return name.contains("carbon")
        }
        let carbonBuckets = carbonGroup?["buckets"] as? [[String: Any]] ?? []
        let carbonBucket = carbonBuckets.first { ($0["window"] as? String) == "weekly" }
            ?? carbonBuckets.first
            ?? allBuckets.first {
                let id = ($0["bucketId"] as? String ?? "").lowercased()
                let name = ($0["displayName"] as? String ?? "").lowercased()
                return id.contains("carbon") || name.contains("carbon")
            }

        let isCarbonAvailable = (carbonBucket != nil)
        let carbonPercentage: Int? = isCarbonAvailable ? (usedPercentage(for: carbonBucket) ?? 0) : 0
        let carbonResetTime: String? = isCarbonAvailable ? resetTime(for: carbonBucket, timeZone: timeZone) : nil
        let carbonLabel: String = carbonBucket != nil
            ? scopedLabel(for: carbonGroup?["displayName"] as? String, bucket: carbonBucket!)
            : "Weekly (Carbon)"

        // Find Hydrogen buckets in retrieveUserQuotaSummary, or fall back to fetchAvailableModels
        let hydrogen = parseHydrogenUsage(
            groups: groups,
            allBuckets: allBuckets,
            modelsData: modelsData,
            timeZone: timeZone
        )

        let hasUsage = session != nil || weekly != nil || firstScoped != nil || isCarbonAvailable || hydrogen.isAvailable

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
            "carbonWeeklyPercentage": carbonPercentage as Any,
            "carbonWeeklyResetTime": carbonResetTime as Any,
            "carbonWeeklyLabel": carbonLabel as Any,
            "isCarbonAvailable": isCarbonAvailable as Any,
            "hydrogenDailyPercentage": hydrogen.dailyPercentage as Any,
            "hydrogenDailyResetTime": hydrogen.dailyResetTime as Any,
            "hydrogenDailyLabel": hydrogen.dailyLabel as Any,
            "hydrogenWeeklyPercentage": hydrogen.weeklyPercentage as Any,
            "hydrogenWeeklyResetTime": hydrogen.weeklyResetTime as Any,
            "hydrogenWeeklyLabel": hydrogen.weeklyLabel as Any,
            "isHydrogenAvailable": hydrogen.isAvailable as Any,
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
        if let (data, status) = try? await postJSON(url: loadCodeAssistURL, body: body, accessToken: accessToken, session: session),
           status == 200 {
            return parsePlanName(from: data, fallbackTier: fallbackTier)
        }
        if let (data, status) = try? await postJSON(url: fallbackLoadCodeAssistURL, body: body, accessToken: accessToken, session: session),
           status == 200 {
            return parsePlanName(from: data, fallbackTier: fallbackTier)
        }
        return formatTierName(fallbackTier)
    }

    private static func fetchAvailableModelsData(accessToken: String, httpStatus: Int, session: URLSession) async -> Data? {
        guard httpStatus == 200 else { return nil }
        let body = Data("{}".utf8)
        if let (data, status) = try? await postJSON(url: availableModelsURL, body: body, accessToken: accessToken, session: session),
           status == 200 {
            return data
        }
        if let (data, status) = try? await postJSON(url: fallbackAvailableModelsURL, body: body, accessToken: accessToken, session: session),
           status == 200 {
            return data
        }
        return nil
    }

    private struct HydrogenUsage {
        let dailyPercentage: Int?
        let dailyResetTime: String?
        let dailyLabel: String?
        let weeklyPercentage: Int?
        let weeklyResetTime: String?
        let weeklyLabel: String
        let isAvailable: Bool
    }

    private static func parseHydrogenUsage(
        groups: [[String: Any]],
        allBuckets: [[String: Any]],
        modelsData: Data?,
        timeZone: TimeZone
    ) -> HydrogenUsage {
        let hydrogenGroup = groups.first {
            let name = ($0["displayName"] as? String ?? "").lowercased()
            return name.contains("hydrogen")
        }
        let groupBuckets = hydrogenGroup?["buckets"] as? [[String: Any]] ?? []
        let matchingBuckets = !groupBuckets.isEmpty
            ? groupBuckets
            : allBuckets.filter {
                let id = ($0["bucketId"] as? String ?? "").lowercased()
                let name = ($0["displayName"] as? String ?? "").lowercased()
                return id.contains("hydrogen") || name.contains("hydrogen")
            }

        if !matchingBuckets.isEmpty {
            let sessionBucket = matchingBuckets.first {
                ($0["bucketId"] as? String)?.lowercased().contains("5h") == true || ($0["window"] as? String) == "5h"
            }
            let weeklyBucket = matchingBuckets.first { ($0["window"] as? String) == "weekly" }
                ?? matchingBuckets.first { $0["bucketId"] as? String != sessionBucket?["bucketId"] as? String }
                ?? matchingBuckets.first
            return HydrogenUsage(
                dailyPercentage: usedPercentage(for: sessionBucket),
                dailyResetTime: resetTime(for: sessionBucket, timeZone: timeZone),
                dailyLabel: sessionBucket != nil ? "Session (Hydrogen)" : nil,
                weeklyPercentage: weeklyBucket.flatMap { usedPercentage(for: $0) } ?? 0,
                weeklyResetTime: resetTime(for: weeklyBucket, timeZone: timeZone),
                weeklyLabel: weeklyBucket.map { scopedLabel(for: hydrogenGroup?["displayName"] as? String, bucket: $0) } ?? "Weekly (Hydrogen)",
                isAvailable: true
            )
        }

        if let modelsData,
           let json = try? JSONSerialization.jsonObject(with: modelsData) as? [String: Any],
           let models = json["models"] as? [String: Any] {
            let hydrogenEntries: [(key: String, info: [String: Any])] = models.compactMap { key, value in
                guard let info = value as? [String: Any] else { return nil }
                let displayName = (info["displayName"] as? String ?? "").lowercased()
                guard key.lowercased().contains("hydrogen") || displayName.contains("hydrogen") else { return nil }
                guard (info["disabled"] as? Bool) != true else { return nil }
                return (key: key, info: info)
            }
            let preferred = hydrogenEntries.first { $0.key.lowercased().contains("medium") }
                ?? hydrogenEntries.first { $0.info["quotaInfo"] is [String: Any] }
            if let quotaInfo = preferred?.info["quotaInfo"] as? [String: Any] {
                return HydrogenUsage(
                    dailyPercentage: nil,
                    dailyResetTime: nil,
                    dailyLabel: nil,
                    weeklyPercentage: usedPercentage(for: quotaInfo) ?? 0,
                    weeklyResetTime: resetTime(for: quotaInfo, timeZone: timeZone),
                    weeklyLabel: "Weekly (Hydrogen)",
                    isAvailable: true
                )
            }
        }

        return HydrogenUsage(
            dailyPercentage: nil,
            dailyResetTime: nil,
            dailyLabel: nil,
            weeklyPercentage: 0,
            weeklyResetTime: nil,
            weeklyLabel: "Weekly (Hydrogen)",
            isAvailable: false
        )
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
        let nonPrimaryGroups = groups.filter { group in
            let name = (group["displayName"] as? String ?? "").lowercased()
            return name != "gemini models" && !name.contains("carbon") && !name.contains("hydrogen")
        }
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
        if lower.contains("carbon") { return "Weekly (Carbon)" }
        if lower.contains("hydrogen") { return "Weekly (Hydrogen)" }
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
