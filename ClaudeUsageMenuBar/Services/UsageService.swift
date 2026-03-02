import Foundation
import Combine
import WebKit

@MainActor
class UsageService: NSObject, ObservableObject, WKNavigationDelegate {

    // MARK: - Constants

    enum Constants {
        static let refreshInterval: TimeInterval = 30
        static let timerInterval: TimeInterval = 1.0
        static let initialRefreshDelay: TimeInterval = 2.0
        static let scrapeDelay: TimeInterval = 2.0
        static let refreshTimeout: TimeInterval = 30
        static let backgroundWebViewSize = CGSize(width: 1024, height: 768)
    }

    // MARK: - Published Properties

    @Published var usageData = UsageData()
    @Published var isRefreshing = false
    @Published var countdown: Int = Int(Constants.refreshInterval)
    @Published var dailyResetCountdown: String?
    @Published var weeklyResetCountdown: String?
    @Published var debugInfo: String = ""

    // MARK: - Private Properties

    private var countdownTimer: Timer?
    private var backgroundWebView: WKWebView?
    private var rawDailyResetTime: String?
    private var rawWeeklyResetTime: String?
    var refreshStartTime: Date?  // internal for @testable import

    var displayText: String {
        usageData.displayPercentage
    }

    override init() {
        super.init()
        setupBackgroundWebView()
        startAutoRefresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.initialRefreshDelay) { [weak self] in
            self?.triggerRefresh()
        }
    }

    private func setupBackgroundWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let frame = CGRect(origin: .zero, size: Constants.backgroundWebViewSize)
        let webView = WKWebView(frame: frame, configuration: configuration)
        webView.navigationDelegate = self
        self.backgroundWebView = webView
    }

    // MARK: - Public Methods

    func triggerRefresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshStartTime = Date()
        usageData.errorMessage = nil

        guard let webView = backgroundWebView,
              let url = URL(string: "https://claude.ai/settings/usage") else {
            setError("WebView not available")
            return
        }
        webView.load(URLRequest(url: url))
    }

    func logout() {
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()

        dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
            let claudeRecords = records.filter { $0.displayName.contains("claude") || $0.displayName.contains("anthropic") }
            dataStore.removeData(ofTypes: dataTypes, for: claudeRecords) { [weak self] in
                Task { @MainActor in
                    self?.resetToLoggedOut()
                }
            }
        }
    }

    func clearCache() {
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let sinceDate = Date.distantPast

        dataStore.removeData(ofTypes: dataTypes, modifiedSince: sinceDate) { [weak self] in
            Task { @MainActor in
                self?.resetToLoggedOut()
                self?.setupBackgroundWebView()
            }
        }
    }

    // MARK: - State Updates

    func setError(_ message: String) {
        usageData.errorMessage = message
        isRefreshing = false
        refreshStartTime = nil
        resetCountdown()
    }

    func setLoggedOut() {
        usageData.isLoggedIn = false
        usageData.percentage = nil
        isRefreshing = false
        refreshStartTime = nil
        resetCountdown()
    }

    private func resetToLoggedOut() {
        usageData = UsageData()
        dailyResetCountdown = nil
        weeklyResetCountdown = nil
        rawDailyResetTime = nil
        rawWeeklyResetTime = nil
        setLoggedOut()
        usageData.errorMessage = "Logged out. Click 'Open Usage Page / Login' to sign in."
    }

    private func applyScrapedData(_ data: ScrapedUsageData) {
        usageData.percentage = data.percentage
        usageData.messagesUsed = data.messagesUsed
        usageData.messagesLimit = data.messagesLimit
        usageData.resetTime = data.resetTime
        usageData.weeklyPercentage = data.weeklyPercentage
        usageData.weeklyMessagesUsed = data.weeklyMessagesUsed
        usageData.weeklyMessagesLimit = data.weeklyMessagesLimit
        usageData.weeklyResetTime = data.weeklyResetTime
        usageData.email = data.email
        usageData.organizationName = data.organizationName
        usageData.planName = data.planName
        usageData.lastUpdated = Date()
        usageData.isLoggedIn = true
        usageData.errorMessage = nil

        rawDailyResetTime = data.resetTime
        rawWeeklyResetTime = data.weeklyResetTime
        updateResetCountdowns()

        isRefreshing = false
        refreshStartTime = nil
        resetCountdown()
    }

    // MARK: - Auto Refresh

    private func startAutoRefresh() {
        countdown = Int(Constants.refreshInterval)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: Constants.timerInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handleTimerTick()
            }
        }
    }

    private func handleTimerTick() {
        updateResetCountdowns()

        if isRefreshing {
            checkForRefreshTimeout()
            return
        }

        if countdown > 0 {
            countdown -= 1
        } else {
            triggerRefresh()
        }
    }

    func checkForRefreshTimeout(currentDate: Date = Date()) {  // internal for @testable import
        guard let startTime = refreshStartTime else { return }

        let elapsed = currentDate.timeIntervalSince(startTime)
        if elapsed > Constants.refreshTimeout {
            recoverFromStuckRefresh()
        }
    }

    func recoverFromStuckRefresh() {  // internal for @testable import
        refreshStartTime = nil
        isRefreshing = false
        setupBackgroundWebView()
        setError("Refresh timed out. Will retry automatically.")
    }

    private func resetCountdown() {
        countdown = Int(Constants.refreshInterval)
    }

    private func updateResetCountdowns() {
        dailyResetCountdown = rawDailyResetTime
        weeklyResetCountdown = WeeklyCountdownCalculator.calculate(from: rawWeeklyResetTime)
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            self?.handleNavigationFinished(webView: webView)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            self?.setError("Navigation failed: \(error.localizedDescription)")
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            self?.setError("Load failed: \(error.localizedDescription)")
        }
    }

    private func handleNavigationFinished(webView: WKWebView) {
        guard let url = webView.url else { return }
        let urlString = url.absoluteString.lowercased()

        if urlString.contains("/login") || urlString.contains("/signin") {
            setLoggedOut()
            setError("Please log in via 'Open Usage Page'")
            return
        }

        if urlString.contains("/settings/usage") {
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.scrapeDelay) { [weak self] in
                self?.scrapeUsage(from: webView)
            }
            return
        }

        if urlString.contains("claude.ai") && !urlString.contains("/oauth") && !urlString.contains("/callback") {
            if let usageURL = URL(string: "https://claude.ai/settings/usage") {
                webView.load(URLRequest(url: usageURL))
            }
        }
    }

    // MARK: - Scraping

    private func scrapeUsage(from webView: WKWebView) {
        webView.evaluateJavaScript(UsageScrapingScript.script) { [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.handleScrapingResult(result, error: error)
            }
        }
    }

    private func handleScrapingResult(_ result: Any?, error: Error?) {
        if let error = error {
            setError("Script error: \(error.localizedDescription)")
            return
        }

        guard let dict = result as? [String: Any] else {
            setError("Invalid response format")
            return
        }

        debugInfo = dict["debug"] as? String ?? ""

        guard let success = dict["success"] as? Bool, success else {
            setError(dict["error"] as? String ?? "Failed to parse usage")
            return
        }

        let data = ScrapedUsageData(
            percentage: dict["percentage"] as? Int ?? 0,
            messagesUsed: dict["messagesUsed"] as? Int,
            messagesLimit: dict["messagesLimit"] as? Int,
            resetTime: dict["resetTime"] as? String,
            weeklyPercentage: dict["weeklyPercentage"] as? Int,
            weeklyMessagesUsed: dict["weeklyMessagesUsed"] as? Int,
            weeklyMessagesLimit: dict["weeklyMessagesLimit"] as? Int,
            weeklyResetTime: dict["weeklyResetTime"] as? String,
            email: dict["email"] as? String,
            organizationName: dict["orgName"] as? String,
            planName: dict["planName"] as? String
        )
        applyScrapedData(data)
    }
}

// MARK: - Supporting Types

private struct ScrapedUsageData {
    let percentage: Int
    let messagesUsed: Int?
    let messagesLimit: Int?
    let resetTime: String?
    let weeklyPercentage: Int?
    let weeklyMessagesUsed: Int?
    let weeklyMessagesLimit: Int?
    let weeklyResetTime: String?
    let email: String?
    let organizationName: String?
    let planName: String?
}

// MARK: - Weekly Countdown Calculator

enum WeeklyCountdownCalculator {
    private static let dayAbbreviations = ["Sun": 1, "Mon": 2, "Tue": 3, "Wed": 4, "Thu": 5, "Fri": 6, "Sat": 7]

    static func calculate(from resetString: String?, currentDate: Date = Date()) -> String? {
        guard let resetString = resetString else { return nil }

        guard let weekday = extractWeekday(from: resetString),
              let (hour, minute) = extractTime(from: resetString) else {
            return resetString
        }

        guard let targetDate = calculateTargetDate(weekday: weekday, hour: hour, minute: minute, from: currentDate) else {
            return resetString
        }

        return formatCountdown(from: currentDate, to: targetDate)
    }

    static func extractWeekday(from string: String) -> Int? {
        for (abbrev, weekday) in dayAbbreviations {
            if string.contains(abbrev) { return weekday }
        }
        return nil
    }

    static func extractTime(from string: String) -> (hour: Int, minute: Int)? {
        let pattern = #"(\d{1,2}):(\d{2})\s*(AM|PM)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              let hourRange = Range(match.range(at: 1), in: string),
              let minuteRange = Range(match.range(at: 2), in: string),
              let ampmRange = Range(match.range(at: 3), in: string) else {
            return nil
        }

        var hour = Int(string[hourRange]) ?? 0
        let minute = Int(string[minuteRange]) ?? 0
        let ampm = String(string[ampmRange]).uppercased()

        if ampm == "PM" && hour != 12 { hour += 12 }
        else if ampm == "AM" && hour == 12 { hour = 0 }

        return (hour, minute)
    }

    static func calculateTargetDate(weekday: Int, hour: Int, minute: Int, from currentDate: Date = Date()) -> Date? {
        let calendar = Calendar.current
        let currentWeekday = calendar.component(.weekday, from: currentDate)

        var daysUntilReset = weekday - currentWeekday
        if daysUntilReset < 0 { daysUntilReset += 7 }

        guard var targetDate = calendar.date(byAdding: .day, value: daysUntilReset, to: currentDate) else { return nil }
        targetDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: targetDate) ?? targetDate

        if targetDate <= currentDate {
            targetDate = calendar.date(byAdding: .day, value: 7, to: targetDate) ?? targetDate
        }

        return targetDate
    }

    static func formatCountdown(from currentDate: Date = Date(), to targetDate: Date) -> String {
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: currentDate, to: targetDate)
        var parts: [String] = []

        if let days = components.day, days > 0 { parts.append("\(days)d") }
        if let hours = components.hour, hours > 0 { parts.append("\(hours)hr") }
        if let minutes = components.minute, minutes > 0 { parts.append("\(minutes)min") }

        return parts.isEmpty ? "< 1min" : parts.joined(separator: " ")
    }
}

// MARK: - JavaScript Scraping Script

enum UsageScrapingScript {
    static let script = """
    (function() {
        const result = {
            success: false,
            percentage: null,
            messagesUsed: null,
            messagesLimit: null,
            resetTime: null,
            weeklyPercentage: null,
            weeklyMessagesUsed: null,
            weeklyMessagesLimit: null,
            weeklyResetTime: null,
            email: null,
            orgName: null,
            planName: null,
            error: null,
            debug: ''
        };

        try {
            // Extract from __next_f (Next.js streaming data)
            if (window.__next_f && Array.isArray(window.__next_f)) {
                for (const entry of window.__next_f) {
                    if (!Array.isArray(entry) || entry.length < 2) continue;
                    const content = String(entry[1] || '');

                    // Organization from memberships
                    if (!result.orgName) {
                        const orgMatch = content.match(/"memberships":\\s*\\[\\s*\\{[^\\]]*"organization"\\s*:\\s*\\{[^}]*"name"\\s*:\\s*"([^"]+)"/);
                        if (orgMatch) result.orgName = orgMatch[1];
                    }

                    // Email
                    if (!result.email) {
                        const emailMatch = content.match(/"email_address"\\s*:\\s*"([^"]+@[^"]+)"/);
                        if (emailMatch) result.email = emailMatch[1];
                    }
                }
            }

            // Extract from page text
            const bodyText = document.body.innerText;

            // Primary: Look for "X% used" pattern (more reliable)
            const percentUsedPattern = /(\\d+)\\s*%\\s*used/gi;
            const percentMatches = [...bodyText.matchAll(percentUsedPattern)];

            if (percentMatches.length >= 1) {
                result.percentage = parseInt(percentMatches[0][1]);
            }
            if (percentMatches.length >= 2) {
                result.weeklyPercentage = parseInt(percentMatches[1][1]);
            }

            // Secondary: Look for "X / Y" or "X of Y" patterns for message counts
            const usagePatterns = bodyText.match(/(\\d+)\\s*(?:\\/|of)\\s*(\\d+)/gi) || [];

            if (usagePatterns.length >= 1) {
                const numbers = usagePatterns[0].match(/(\\d+)/g);
                if (numbers && numbers.length >= 2) {
                    result.messagesUsed = parseInt(numbers[0]);
                    result.messagesLimit = parseInt(numbers[1]);
                    // Only use this for percentage if we didn't find "X% used"
                    if (result.percentage === null && result.messagesLimit > 0) {
                        result.percentage = Math.round((result.messagesUsed / result.messagesLimit) * 100);
                    }
                }
            }

            if (usagePatterns.length >= 2) {
                const numbers = usagePatterns[1].match(/(\\d+)/g);
                if (numbers && numbers.length >= 2) {
                    result.weeklyMessagesUsed = parseInt(numbers[0]);
                    result.weeklyMessagesLimit = parseInt(numbers[1]);
                    // Only use this for percentage if we didn't find "X% used"
                    if (result.weeklyPercentage === null && result.weeklyMessagesLimit > 0) {
                        result.weeklyPercentage = Math.round((result.weeklyMessagesUsed / result.weeklyMessagesLimit) * 100);
                    }
                }
            }

            // Fallback: Look for standalone percentages
            if (result.percentage === null || result.weeklyPercentage === null) {
                const standalonePercents = bodyText.match(/(\\d+)\\s*%/g) || [];
                if (standalonePercents.length >= 1 && result.percentage === null) {
                    result.percentage = parseInt(standalonePercents[0]);
                }
                if (standalonePercents.length >= 2 && result.weeklyPercentage === null) {
                    result.weeklyPercentage = parseInt(standalonePercents[1]);
                }
            }

            // Reset times
            const timePattern = /(\\d+\\s*(?:hours?|hrs?|h)(?:\\s*\\d+\\s*(?:minutes?|mins?|m))?|\\d+\\s*(?:minutes?|mins?|m))/gi;
            const timeMatches = bodyText.match(timePattern) || [];
            if (timeMatches.length >= 1) result.resetTime = timeMatches[0].trim();

            const dayTimePattern = /((?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\\s+\\d{1,2}:\\d{2}\\s*(?:AM|PM))/gi;
            const dayTimeMatches = bodyText.match(dayTimePattern) || [];
            if (dayTimeMatches.length >= 1) result.weeklyResetTime = dayTimeMatches[0].trim();

            // Plan name
            if (!result.planName) {
                const planMatch = bodyText.match(/\\b(Team|Pro|Free|Enterprise|Max|Business)\\b/i);
                if (planMatch) result.planName = planMatch[1];
            }

            // Email fallback from page text
            if (!result.email) {
                const emailMatch = bodyText.match(/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}/);
                if (emailMatch) result.email = emailMatch[0];
            }

            result.success = result.percentage !== null || result.messagesUsed !== null || result.email !== null;
            if (!result.success) result.error = 'No usage data found';

            // Debug info
            result.debug = 'Scraped: ' + JSON.stringify({
                percentage: result.percentage,
                email: result.email,
                orgName: result.orgName,
                planName: result.planName
            });

        } catch (e) {
            result.error = 'Script error: ' + e.message;
        }

        return result;
    })();
    """
}
