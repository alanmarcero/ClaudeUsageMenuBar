import Foundation

// Reads Gemini usage the same way `agy -p /usage` does: it reads the OAuth token
// that the Gemini / Antigravity CLI saves in the macOS Keychain under service "gemini"
// and posts to Cloud Code's retrieveUserQuotaSummary and loadCodeAssist endpoints.
// When the access token expires or nears expiration, it delegates renewal to the
// local CLI (`agy` / `gemini`) rather than embedding OAuth client credentials.
enum GeminiUsageAPI {
    static let quotaURL = URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")!
    static let loadCodeAssistURL = URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!
    static let availableModelsURL = URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels")!
    static let fallbackQuotaURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")!
    static let fallbackLoadCodeAssistURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!
    static let fallbackAvailableModelsURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels")!
    static let keychainService = "gemini"
    static let keychainAccount = "antigravity"
    static let proactiveRefreshWindow: TimeInterval = 300 // 5 minutes
    static let requestTimeout: TimeInterval = 20
    static let expiredLoginMessage = "Gemini CLI's login has expired. Run agy in Terminal to renew it."
    static let userAgent = "antigravity/cli/1.5.1 (aidev_client; os_type=darwin; arch=arm64; cl=1014269460; auth_method=consumer)"

    nonisolated(unsafe) static var onRefreshLogin: ((Login) -> Login?)? = nil

    private static let keyringBase64Prefix = "go-keyring-base64:"
    private static let keyringHexPrefix = "go-keyring-encoded:"

    enum LoginSource: Equatable {
        case antigravityFile
        case oauthCredsFile
        case keychain
        case unknown
    }

    struct Login: Equatable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
        let authMethod: String?
        let email: String?
        let userTier: String?
        let rawPayload: [String: Any]?
        let source: LoginSource

        init(
            accessToken: String,
            refreshToken: String? = nil,
            expiresAt: Date? = nil,
            authMethod: String? = nil,
            email: String? = nil,
            userTier: String? = nil,
            rawPayload: [String: Any]? = nil,
            source: LoginSource = .unknown
        ) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresAt = expiresAt
            self.authMethod = authMethod
            self.email = email
            self.userTier = userTier
            self.rawPayload = rawPayload
            self.source = source
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

    static var antigravityTokenURL: URL {
        realUserHomeDirectory.appendingPathComponent(".gemini/antigravity-cli/antigravity-oauth-token")
    }

    static var oauthCredsURL: URL {
        realUserHomeDirectory.appendingPathComponent(".gemini/oauth_creds.json")
    }

    // Reads the active Gemini / Antigravity CLI login from disk (`~/.gemini/antigravity-cli/antigravity-oauth-token`),
    // macOS Keychain (`service: "gemini"`), or `~/.gemini/oauth_creds.json`, picking the freshest credential.
    static func readLogin() -> Login? {
        let candidates = [
            readLoginFromFile(at: antigravityTokenURL, source: .antigravityFile),
            readLoginFromKeychain(),
            readLoginFromFile(at: oauthCredsURL, source: .oauthCredsFile)
        ].compactMap { $0 }

        return candidates.max { lhs, rhs in
            let lhsHasRefresh = (lhs.refreshToken?.isEmpty == false)
            let rhsHasRefresh = (rhs.refreshToken?.isEmpty == false)
            if lhsHasRefresh != rhsHasRefresh {
                return !lhsHasRefresh && rhsHasRefresh
            }
            let lhsExp = lhs.expiresAt ?? .distantPast
            let rhsExp = rhs.expiresAt ?? .distantPast
            return lhsExp < rhsExp
        }
    }

    static func readLoginFromFile(at url: URL, source: LoginSource) -> Login? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parseLogin(data, source: source)
    }

    // Reads through /usr/bin/security so the item's ACL (written by go-keyring via
    // /usr/bin/security) grants access without prompting on ad hoc signed updates.
    static func readLoginFromKeychain() -> Login? {
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
        return parseLogin(data, source: .keychain)
    }

    static func parseLogin(_ data: Data, source: LoginSource = .unknown) -> Login? {
        guard let decoded = decodeKeychainPayload(data),
              let root = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any] else {
            return nil
        }

        // Format 1: antigravity-oauth-token / go-keyring (`{ "token": { "access_token": ..., "expiry": ... } }`)
        if let token = root["token"] as? [String: Any] {
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
                rawPayload: root,
                source: source
            )
        }

        // Format 2: ~/.gemini/oauth_creds.json (`{ "access_token": ..., "expiry_date": 1763391512000 }`)
        let accessToken = (root["access_token"] as? String) ?? ""
        guard !accessToken.isEmpty else { return nil }
        let refreshToken = nonEmpty(root["refresh_token"] as? String)
        let expiresAt: Date? = (root["expiry_date"] as? NSNumber).map {
            Date(timeIntervalSince1970: $0.doubleValue / 1000.0)
        } ?? (root["expiry"] as? String).flatMap(parseISODate)

        return Login(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            authMethod: nonEmpty(root["auth_method"] as? String),
            email: nonEmpty(root["id_token_email"] as? String),
            userTier: nonEmpty(root["user_tier"] as? String),
            rawPayload: root,
            source: source
        )
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

        return await Task.detached(operation: { refreshLoginViaCLI() }).value
    }

    static func refreshLoginViaCLI() -> Login? {
        guard let cliURL = findCLIExecutable() else { return nil }
        let realHome = realUserHomeDirectory
        let process = Process()
        process.executableURL = cliURL
        process.arguments = ["-p", "/usage"]
        process.environment = [
            "HOME": realHome.path,
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]
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

    static func isTrustedCLIPath(_ path: String) -> Bool {
        let trustedPrefixes = ["/opt/homebrew/bin/", "/usr/local/bin/"]
        guard trustedPrefixes.contains(where: { path.hasPrefix($0) }),
              FileManager.default.isExecutableFile(atPath: path) else {
            return false
        }
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let realLocalBin = realUserHomeDirectory.appendingPathComponent(".local/").path
        let containerLocalBin = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/").path
        guard !resolvedPath.hasPrefix(realLocalBin),
              !resolvedPath.hasPrefix(containerLocalBin),
              !resolvedPath.hasPrefix("/tmp/"),
              !resolvedPath.hasPrefix("/var/tmp/") else {
            return false
        }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: resolvedPath),
              let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue,
              (perms & 0o002) == 0 else {
            return false
        }
        return true
    }

    static func findCLIExecutable() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/agy",
            "/opt/homebrew/bin/gemini",
            "/usr/local/bin/agy",
            "/usr/local/bin/gemini"
        ]
        guard let match = candidates.first(where: isTrustedCLIPath) else {
            return nil
        }
        return URL(fileURLWithPath: match)
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
            } else if currentLogin.source != .unknown,
                      let diskLogin = readLogin(),
                      diskLogin.accessToken != currentLogin.accessToken,
                      !diskLogin.isExpiredOrExpiringSoon(now: now, window: 0) {
                // CLI may have renewed the token on disk while the app was idle/asleep.
                currentLogin = diskLogin
            }
        }

        if let expiresAt = currentLogin.expiresAt, expiresAt <= now {
            return result(["success": false, "error": expiredLoginMessage], debug: ["source": "geminiLogin", "loginExpired": true])
        }

        do {
            var (data, httpStatus) = try await postJSON(url: quotaURL, body: Data("{}".utf8), accessToken: currentLogin.accessToken, session: session)

            if httpStatus == 401 {
                if let refreshed = await refreshLogin(currentLogin, session: session) {
                    currentLogin = refreshed
                    let retryResult = try await postJSON(url: quotaURL, body: Data("{}".utf8), accessToken: currentLogin.accessToken, session: session)
                    data = retryResult.0
                    httpStatus = retryResult.1
                } else if currentLogin.source != .unknown,
                          let diskLogin = readLogin(),
                          diskLogin.accessToken != currentLogin.accessToken {
                    currentLogin = diskLogin
                    let retryResult = try await postJSON(url: quotaURL, body: Data("{}".utf8), accessToken: currentLogin.accessToken, session: session)
                    data = retryResult.0
                    httpStatus = retryResult.1
                }
            }

            if httpStatus != 200 && httpStatus != 401 {
                if let fallbackResult = try? await postJSON(url: fallbackQuotaURL, body: Data("{}".utf8), accessToken: currentLogin.accessToken, session: session),
                   fallbackResult.1 == 200 {
                    data = fallbackResult.0
                    httpStatus = fallbackResult.1
                }
            }

            let activeToken = currentLogin.accessToken
            let activeTier = currentLogin.userTier
            let activeEmail = currentLogin.email
            async let planNameTask = fetchPlanName(accessToken: activeToken, fallbackTier: activeTier, httpStatus: httpStatus, session: session)
            async let modelsDataTask = fetchAvailableModelsData(accessToken: activeToken, httpStatus: httpStatus, session: session)
            let planName = await planNameTask
            let modelsData = await modelsDataTask
            return usageResult(from: data, modelsData: modelsData, httpStatus: httpStatus, email: activeEmail, planName: planName)
        } catch {
            let fallbackToken = currentLogin.accessToken
            let fallbackTier = currentLogin.userTier
            let fallbackEmail = currentLogin.email
            if let fallbackResult = try? await postJSON(url: fallbackQuotaURL, body: Data("{}".utf8), accessToken: fallbackToken, session: session),
               fallbackResult.1 == 200 {
                async let planNameTask = fetchPlanName(accessToken: fallbackToken, fallbackTier: fallbackTier, httpStatus: fallbackResult.1, session: session)
                async let modelsDataTask = fetchAvailableModelsData(accessToken: fallbackToken, httpStatus: fallbackResult.1, session: session)
                let planName = await planNameTask
                let modelsData = await modelsDataTask
                return usageResult(from: fallbackResult.0, modelsData: modelsData, httpStatus: fallbackResult.1, email: fallbackEmail, planName: planName)
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

        let thirdPartyGroup = groups.first {
            UsageData.isClaudeGPTLabel($0["displayName"] as? String)
        }
        let thirdPartyBuckets = thirdPartyGroup?["buckets"] as? [[String: Any]] ?? []
        let thirdPartySession = thirdPartyBuckets.first {
            ($0["bucketId"] as? String)?.contains("5h") == true || ($0["window"] as? String) == "5h"
        } ?? allBuckets.first {
            let id = ($0["bucketId"] as? String ?? "").lowercased()
            let name = ($0["displayName"] as? String ?? "").lowercased()
            return (UsageData.isClaudeGPTLabel(id) || UsageData.isClaudeGPTLabel(name))
                && (id.contains("5h") || ($0["window"] as? String) == "5h")
        }

        let extraRows = buildExtraRows(from: groups, allBuckets: allBuckets, modelsData: modelsData, timeZone: timeZone)
        let isPrimarySessionDisabled = (session?["disabled"] as? Bool) == true
        let isThirdPartySessionDisabled = (thirdPartySession?["disabled"] as? Bool) == true
        let hasUsage = session != nil || weekly != nil || firstScoped != nil || thirdPartySession != nil || !extraRows.isEmpty

        let fields: [String: Any] = [
            "success": hasUsage,
            "error": (hasUsage ? nil : "No Gemini usage limits in the response. See body in debug.") as Any,
            "percentage": (isPrimarySessionDisabled ? nil : usedPercentage(for: session)) as Any,
            "resetTime": (isPrimarySessionDisabled ? nil : resetTime(for: session, timeZone: timeZone)) as Any,
            "isSessionDisabled": isPrimarySessionDisabled,
            "weeklyPercentage": usedPercentage(for: weekly) as Any,
            "weeklyResetTime": resetTime(for: weekly, timeZone: timeZone) as Any,
            "geminiSharedDescription": nonEmpty(geminiGroup?["description"] as? String) as Any,
            "geminiThirdPartyDescription": nonEmpty(thirdPartyGroup?["description"] as? String) as Any,
            "geminiExtraRows": extraRows,
            "sonnetWeeklyPercentage": usedPercentage(for: firstScoped?.bucket) as Any,
            "sonnetWeeklyResetTime": resetTime(for: firstScoped?.bucket, timeZone: timeZone) as Any,
            "sonnetWeeklyLabel": firstScoped?.label as Any,
            "designDailyPercentage": (isThirdPartySessionDisabled ? nil : usedPercentage(for: thirdPartySession)) as Any,
            "designDailyResetTime": (isThirdPartySessionDisabled ? nil : resetTime(for: thirdPartySession, timeZone: timeZone)) as Any,
            "designDailyLabel": (thirdPartySession != nil ? "Session (Claude / GPT)" : nil) as Any,
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

    // Builds dedicated rows for any model or model group that has its OWN quota pool
    // (either as its own group in retrieveUserQuotaSummary, or in fetchAvailableModels with a
    // quotaInfo resetTime not shared with any group bucket in retrieveUserQuotaSummary).
    private static func buildExtraRows(
        from groups: [[String: Any]],
        allBuckets: [[String: Any]],
        modelsData: Data?,
        timeZone: TimeZone
    ) -> [[String: Any]] {
        let dedicatedGroups = groups.filter { group in
            let name = (group["displayName"] as? String ?? "").lowercased()
            return name != "gemini models" && !UsageData.isClaudeGPTLabel(name)
        }

        let groupRows: [[String: Any]] = dedicatedGroups.flatMap { group -> [[String: Any]] in
            let groupName = group["displayName"] as? String
            let short = shortPoolName(from: groupName)
            let helpText = nonEmpty(group["description"] as? String)
            let buckets = group["buckets"] as? [[String: Any]] ?? []
            let sessionBucket = buckets.first {
                ($0["bucketId"] as? String)?.lowercased().contains("5h") == true || ($0["window"] as? String) == "5h"
            }
            let weeklyBucket = buckets.first { ($0["window"] as? String) == "weekly" }
                ?? buckets.first { $0["bucketId"] as? String != sessionBucket?["bucketId"] as? String }
            let weeklyPct = usedPercentage(for: weeklyBucket)
            let linkedWeeklyReached = (weeklyPct ?? 0) >= 100
            let slug = short.lowercased().replacingOccurrences(of: " ", with: "-")

            let sessionRows: [[String: Any]] = sessionBucket.map { bucket in
                let isDisabled = (bucket["disabled"] as? Bool) == true
                return [[
                    "id": "\(slug)-session",
                    "label": "Session (\(short))",
                    "window": "5h",
                    "percentage": (isDisabled ? nil : usedPercentage(for: bucket)) as Any,
                    "resetTime": (isDisabled ? nil : resetTime(for: bucket, timeZone: timeZone)) as Any,
                    "isDisabled": isDisabled,
                    "linkedWeeklyReached": linkedWeeklyReached,
                    "helpText": helpText as Any
                ]]
            } ?? []

            let weeklyRows: [[String: Any]] = weeklyBucket.map { bucket in
                [[
                    "id": "\(slug)-weekly",
                    "label": scopedLabel(for: groupName, bucket: bucket),
                    "window": "weekly",
                    "percentage": weeklyPct as Any,
                    "resetTime": resetTime(for: bucket, timeZone: timeZone) as Any,
                    "isDisabled": false,
                    "linkedWeeklyReached": false,
                    "helpText": helpText as Any
                ]]
            } ?? []

            return sessionRows + weeklyRows
        }

        let standaloneRows = buildStandaloneModelRows(
            from: modelsData,
            groups: groups,
            allBuckets: allBuckets,
            timeZone: timeZone
        )
        return groupRows + standaloneRows
    }

    private static func buildStandaloneModelRows(
        from modelsData: Data?,
        groups: [[String: Any]],
        allBuckets: [[String: Any]],
        timeZone: TimeZone
    ) -> [[String: Any]] {
        guard let modelsData,
              let json = try? JSONSerialization.jsonObject(with: modelsData) as? [String: Any],
              let models = json["models"] as? [String: Any] else {
            return []
        }

        let coveredGroupText = groups
            .compactMap { group -> String? in
                let name = group["displayName"] as? String ?? ""
                let desc = group["description"] as? String ?? ""
                return "\(name) \(desc)".lowercased()
            }
            .joined(separator: " ")

        let groupResetTimes = Set(allBuckets.compactMap { $0["resetTime"] as? String })

        let standaloneEntries: [(baseName: String, shortName: String, quotaInfo: [String: Any], rawReset: String, pct: Int)] = models
            .compactMap { key, value in
                guard !key.lowercased().hasPrefix("tab_"),
                      let info = value as? [String: Any],
                      (info["disabled"] as? Bool) != true,
                      let rawDisplay = nonEmpty(info["displayName"] as? String),
                      let quotaInfo = info["quotaInfo"] as? [String: Any],
                      let rawReset = nonEmpty(quotaInfo["resetTime"] as? String),
                      !groupResetTimes.contains(rawReset) else {
                    return nil
                }
                let baseName = stripEffortSuffix(from: rawDisplay)
                let shortName = shortPoolName(from: baseName)
                if coveredGroupText.contains(baseName.lowercased()) || coveredGroupText.contains(shortName.lowercased()) {
                    return nil
                }
                let pct = usedPercentage(for: quotaInfo) ?? 0
                return (baseName: baseName, shortName: shortName, quotaInfo: quotaInfo, rawReset: rawReset, pct: pct)
            }

        let groupedByPool = Dictionary(grouping: standaloneEntries) { "\($0.rawReset)|\($0.pct)" }
        return groupedByPool.keys.sorted().compactMap { poolKey in
            guard let items = groupedByPool[poolKey], let first = items.first else { return nil }
            let uniqueNames = Array(Set(items.map(\.shortName))).sorted()
            let poolTitle = uniqueNames.joined(separator: " & ")
            let slug = poolTitle.lowercased().replacingOccurrences(of: " ", with: "-")
            return [
                "id": "model-\(slug)",
                "label": "Weekly (\(poolTitle))",
                "window": "weekly",
                "percentage": first.pct,
                "resetTime": resetTime(for: first.quotaInfo, timeZone: timeZone) as Any,
                "isDisabled": false,
                "linkedWeeklyReached": false,
                "helpText": "Dedicated quota for \(Array(Set(items.map(\.baseName))).sorted().joined(separator: ", "))"
            ]
        }
    }

    private static func stripEffortSuffix(from displayName: String) -> String {
        displayName.replacingOccurrences(
            of: #"\s*\((Low|Medium|High|XHigh|Extra)\)\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func shortPoolName(from rawName: String?) -> String {
        let name = nonEmpty(rawName) ?? "Models"
        let lower = name.lowercased()
        if lower.contains("carbon") { return "Carbon" }
        if lower.contains("argon") { return "Argon" }
        if lower.contains("hydrogen") { return "Hydrogen" }
        if lower.contains("neon") { return "Neon" }
        if UsageData.isClaudeGPTLabel(lower) { return "Claude / GPT" }
        return name.replacingOccurrences(of: #"^Gemini\s+\d+(\.\d+)?\s+"#, with: "", options: .regularExpression)
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
            return name != "gemini models"
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
        UsageData.isClaudeGPTLabel(groupName) ? 0 : 1
    }

    private static func scopedLabel(for groupName: String?, bucket: [String: Any]) -> String {
        let name = groupName ?? (bucket["displayName"] as? String) ?? "Models"
        let lower = name.lowercased()
        if lower.contains("argon") { return "Weekly (Argon)" }
        if lower.contains("carbon") { return "Weekly (Carbon)" }
        if lower.contains("hydrogen") { return "Weekly (Hydrogen)" }
        if lower.contains("neon") { return "Weekly (Neon)" }
        if lower.contains("claude") || lower.contains("gpt") || lower.contains("3p") { return "Weekly (Claude / GPT)" }
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
