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
    @Published var sonnetWeeklyResetCountdown: String?
    @Published var designWeeklyResetCountdown: String?
    @Published var debugInfo: String = ""

    // MARK: - Private Properties

    private var countdownTimer: Timer?
    private var backgroundWebView: WKWebView?
    private var rawDailyResetTime: String?
    private var rawWeeklyResetTime: String?
    private var rawSonnetWeeklyResetTime: String?
    private var rawDesignWeeklyResetTime: String?
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
        sonnetWeeklyResetCountdown = nil
        rawDailyResetTime = nil
        rawWeeklyResetTime = nil
        rawSonnetWeeklyResetTime = nil
        setLoggedOut()
        usageData.errorMessage = "Logged out. Click 'Open Usage Page / Login' to sign in."
    }

    private func applyScrapedData(_ data: ScrapedUsageData) {
        usageData.percentage = data.percentage
        usageData.resetTime = data.resetTime
        usageData.weeklyPercentage = data.weeklyPercentage
        usageData.weeklyResetTime = data.weeklyResetTime
        usageData.sonnetWeeklyPercentage = data.sonnetWeeklyPercentage
        usageData.sonnetWeeklyResetTime = data.sonnetWeeklyResetTime
        usageData.designWeeklyPercentage = data.designWeeklyPercentage
        usageData.designWeeklyResetTime = data.designWeeklyResetTime
        usageData.email = data.email
        usageData.organizationName = data.organizationName
        usageData.planName = data.planName
        usageData.lastUpdated = Date()
        usageData.isLoggedIn = true
        usageData.errorMessage = nil

        rawDailyResetTime = data.resetTime
        rawWeeklyResetTime = data.weeklyResetTime
        rawSonnetWeeklyResetTime = data.sonnetWeeklyResetTime
        rawDesignWeeklyResetTime = data.designWeeklyResetTime
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
        sonnetWeeklyResetCountdown = WeeklyCountdownCalculator.calculate(from: rawSonnetWeeklyResetTime)
        designWeeklyResetCountdown = WeeklyCountdownCalculator.calculate(from: rawDesignWeeklyResetTime)
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
        webView.callAsyncJavaScript(
            UsageScrapingScript.script,
            arguments: [:],
            in: nil,
            in: .page
        ) { [weak self] result in
            Task { @MainActor [weak self] in
                switch result {
                case .success(let value):
                    self?.handleScrapingResult(value, error: nil)
                case .failure(let error):
                    self?.handleScrapingResult(nil, error: error)
                }
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
            percentage: dict["percentage"] as? Int,
            resetTime: dict["resetTime"] as? String,
            weeklyPercentage: dict["weeklyPercentage"] as? Int,
            weeklyResetTime: dict["weeklyResetTime"] as? String,
            sonnetWeeklyPercentage: dict["sonnetWeeklyPercentage"] as? Int,
            sonnetWeeklyResetTime: dict["sonnetWeeklyResetTime"] as? String,
            designWeeklyPercentage: dict["designWeeklyPercentage"] as? Int,
            designWeeklyResetTime: dict["designWeeklyResetTime"] as? String,
            email: dict["email"] as? String,
            organizationName: dict["orgName"] as? String,
            planName: dict["planName"] as? String
        )
        applyScrapedData(data)
    }
}

// MARK: - Supporting Types

private struct ScrapedUsageData {
    let percentage: Int?
    let resetTime: String?
    let weeklyPercentage: Int?
    let weeklyResetTime: String?
    let sonnetWeeklyPercentage: Int?
    let sonnetWeeklyResetTime: String?
    let designWeeklyPercentage: Int?
    let designWeeklyResetTime: String?
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
    // Executed via WKWebView.callAsyncJavaScript: the script body IS the async function body,
    // so top-level `await` works and the returned value is the resolved value.
    //
    // The page is fully client-side rendered — on a fresh load, the usage heading and "% used"
    // text appear only after React + react-query fetch and hydrate. We poll for both the DOM
    // to populate and for the react-query cache in IndexedDB to hold account data.
    static let script = """
    const result = {
        success: false,
        percentage: null,
        resetTime: null,
        weeklyPercentage: null,
        weeklyResetTime: null,
        sonnetWeeklyPercentage: null,
        sonnetWeeklyResetTime: null,
        designWeeklyPercentage: null,
        designWeeklyResetTime: null,
        email: null,
        orgName: null,
        planName: null,
        error: null,
        debug: ''
    };

    const sleep = (ms) => new Promise(r => setTimeout(r, ms));
    const limitLabels = ['Current session', 'All models', 'Sonnet only', 'Claude Design'];
    const textSelector = 'span,p,div,h1,h2,h3,h4,a,button';

    const readAccountFromIDB = () => new Promise((resolve) => {
        try {
            const req = indexedDB.open('keyval-store');
            req.onerror = () => resolve(null);
            req.onsuccess = () => {
                try {
                    const db = req.result;
                    const tx = db.transaction('keyval', 'readonly');
                    const store = tx.objectStore('keyval');
                    const get = store.get('react-query-cache');
                    get.onerror = () => resolve(null);
                    get.onsuccess = () => resolve(get.result || null);
                } catch (e) {
                    resolve(null);
                }
            };
            setTimeout(() => resolve(null), 2000);
        } catch (e) {
            resolve(null);
        }
    });

    const findHeading = () => Array.from(document.querySelectorAll('h1, h2, h3'))
        .find(h => (h.textContent || '').trim().toLowerCase().includes('usage limits'));

    const pageHasUsage = () => {
        const bodyText = document.body.innerText || document.body.textContent || '';
        return /%\\s*used/i.test(bodyText) ||
            (document.querySelector('[role="progressbar"]') !== null && limitLabels.some(label => bodyText.includes(label)));
    };

    const cacheHasAccount = (cache) => {
        const queries = cache && cache.clientState && cache.clientState.queries;
        if (!Array.isArray(queries)) return false;
        return queries.some(q => {
            const key = q && q.queryKey;
            if (!Array.isArray(key) || key[0] !== 'current_account') return false;
            return !!(q.state && q.state.data && q.state.data.account);
        });
    };

    const pollAttempts = 60;      // 15s max wait
    const pollIntervalMs = 250;
    const logs = [];

    const normalizeText = (value) => (value || '').replace(/\\s+/g, ' ').trim();

    const getTexts = (container, selector = textSelector) => Array.from(container.querySelectorAll(selector))
        .map(el => normalizeText(el.textContent))
        .filter(text => text && text.length <= 180);

    const labelMatches = (text, label) => {
        const normalized = normalizeText(text).toLowerCase();
        const expected = label.toLowerCase();
        return normalized === expected || normalized.startsWith(expected + ' ');
    };

    const choosePlanLabel = (texts, progressCount) => {
        if (progressCount !== 1) return null;
        const matches = limitLabels.filter(label => texts.some(text => labelMatches(text, label)));
        return matches.length === 1 ? matches[0] : null;
    };

    const parsePercentage = (value) => {
        if (value === null || value === undefined) return null;
        const match = String(value).match(/(\\d+(?:\\.\\d+)?)/);
        return match ? Math.round(Number(match[1])) : null;
    };

    const getProgressPercentage = (progressBar) => {
        const ariaNow = parsePercentage(progressBar.getAttribute('aria-valuenow'));
        if (ariaNow !== null) return ariaNow;

        const ariaText = parsePercentage(progressBar.getAttribute('aria-valuetext'));
        if (ariaText !== null) return ariaText;

        const fill = Array.from(progressBar.children).find(child => child.style && child.style.width);
        return fill ? parsePercentage(fill.style.width) : null;
    };

    const findPlanRowForProgressBar = (progressBar) => {
        let node = progressBar.parentElement;
        while (node && node !== document.body) {
            const progressCount = node.querySelectorAll('[role="progressbar"]').length;
            const label = choosePlanLabel(getTexts(node), progressCount);
            if (label) return { row: node, label };
            node = node.parentElement;
        }
        return null;
    };

    const findGroupByHeading = (row, heading) => {
        let node = row.parentElement;
        while (node && node !== document.body) {
            if (getTexts(node, 'h1,h2,h3,h4').some(text => text === heading)) return node;
            node = node.parentElement;
        }
        return null;
    };

    const findResetTextInTexts = (texts) => texts.find(text =>
        /^resets?\\b/i.test(text) ||
        /\\b\\d+\\s*(?:days?|d|hours?|hrs?|hr|h|minutes?|mins?|min)\\b/i.test(text)
    ) || null;

    const findResetText = (label, row) => {
        const directReset = findResetTextInTexts(getTexts(row));
        if (directReset) return directReset;

        if (label === 'All models' || label === 'Sonnet only' || label === 'Claude Design') {
            const weeklyGroup = findGroupByHeading(row, 'Weekly limits');
            if (weeklyGroup) return findResetTextInTexts(getTexts(weeklyGroup));
        }

        return null;
    };

    const getProgressRowData = (labelText) => {
        const progressBars = Array.from(document.querySelectorAll('[role="progressbar"]'));
        for (const progressBar of progressBars) {
            const planRow = findPlanRowForProgressBar(progressBar);
            if (!planRow || planRow.label !== labelText) continue;

            const percentage = getProgressPercentage(progressBar);
            const resetTime = findResetText(labelText, planRow.row);
            logs.push(`Progressbar data for "${labelText}": %=${percentage}, reset=${resetTime}`);
            return { percentage, resetTime };
        }

        logs.push(`Progressbar row for "${labelText}" not found`);
        return null;
    };

    const getTextRowData = (labelText) => {
        const allElements = Array.from(document.querySelectorAll(textSelector));
        const labelEl = allElements.find(el => labelMatches(el.textContent, labelText));

        if (!labelEl) {
            logs.push(`Label "${labelText}" not found`);
            return null;
        }

        let row = labelEl.parentElement;
        while (row && row !== document.body) {
            const text = row.textContent || '';
            const hasUsage = /\\d+(?:\\.\\d+)?\\s*%\\s*used/i.test(text);
            const hasSingleLabel = limitLabels.filter(label => getTexts(row).some(t => labelMatches(t, label))).length === 1;
            if (hasUsage && hasSingleLabel) break;
            row = row.parentElement;
        }

        if (!row || row === document.body) {
            logs.push(`Text container for "${labelText}" not found`);
            return null;
        }

        const text = row.textContent || '';
        const percentMatch = text.match(/(\\d+(?:\\.\\d+)?)\\s*%\\s*used/i);
        const resetTime = findResetText(labelText, row);
        logs.push(`Text data for "${labelText}": %=${percentMatch?.[1]}, reset=${resetTime}`);

        return {
            percentage: percentMatch ? Math.round(Number(percentMatch[1])) : null,
            resetTime: resetTime || null
        };
    };

    const findRowData = (labelText) => {
        const progressData = getProgressRowData(labelText);
        if (progressData && progressData.percentage !== null) return progressData;
        return getTextRowData(labelText);
    };

    try {
        let cache = null;
        for (let i = 0; i < pollAttempts; i++) {
            if (!cache || !cacheHasAccount(cache)) cache = await readAccountFromIDB();
            // Wait until the usage UI is present. Claude now exposes some rows only through
            // progressbar aria attributes, so "% used" text is not always available.
            if ((findHeading() || pageHasUsage()) && (cacheHasAccount(cache) || pageHasUsage())) break;
            await sleep(pollIntervalMs);
        }

        const queries = (cache && cache.clientState && cache.clientState.queries) || [];
        for (const q of queries) {
            const key = q && q.queryKey;
            if (!Array.isArray(key) || key[0] !== 'current_account') continue;
            const acc = q.state && q.state.data && q.state.data.account;
            if (!acc) continue;
            if (!result.email && acc.email_address) result.email = acc.email_address;
            if (!result.orgName && Array.isArray(acc.memberships) && acc.memberships[0] && acc.memberships[0].organization) {
                result.orgName = acc.memberships[0].organization.name || null;
            }
        }

        const heading = findHeading();
        if (heading) {
            logs.push(`Found heading: ${heading.textContent.trim()}`);
            const row = heading.parentElement;
            if (row) {
                const badge = Array.from(row.children).find(el => el !== heading && el.textContent.trim());
                if (badge) {
                    const text = badge.textContent.trim();
                    if (/^(Team|Pro|Free|Enterprise|Max|Business)$/i.test(text)) result.planName = text;
                }
            }
        } else {
            logs.push('Heading "Your usage limits" not found');
        }

        const daily = findRowData('Current session');
        if (daily) {
            result.percentage = daily.percentage;
            result.resetTime = daily.resetTime;
        }

        const weekly = findRowData('All models');
        if (weekly) {
            result.weeklyPercentage = weekly.percentage;
            result.weeklyResetTime = weekly.resetTime;
        }

        const sonnet = findRowData('Sonnet only');
        if (sonnet) {
            result.sonnetWeeklyPercentage = sonnet.percentage;
            result.sonnetWeeklyResetTime = sonnet.resetTime;
        }

        const design = findRowData('Claude Design');
        if (design) {
            result.designWeeklyPercentage = design.percentage;
            result.designWeeklyResetTime = design.resetTime;
        }

        // Global fallback if labels failed but % used exists
        if (result.percentage === null) {
            const allText = document.body.innerText;
            const percentMatches = [...allText.matchAll(/(\\d+)\\s*%\\s*used/gi)];
            if (percentMatches.length > 0) {
                logs.push(`Fallback: Found ${percentMatches.length} percentages via global search`);
                result.percentage = parseInt(percentMatches[0][1], 10);
                if (percentMatches[1]) result.weeklyPercentage = parseInt(percentMatches[1][1], 10);
                if (percentMatches[2]) result.sonnetWeeklyPercentage = parseInt(percentMatches[2][1], 10);
            }
        }

        result.debug = JSON.stringify({
            daily, weekly, sonnet, design,
            planName: result.planName,
            cacheHasAccount: cacheHasAccount(cache),
            logs,
            url: location.href,
            bodyText: document.body.innerText.substring(0, 1000)
        }, null, 2);

        result.success = result.percentage !== null || result.email !== null;
        if (!result.success) result.error = 'No usage data found. Logs: ' + logs.join(' | ');

    } catch (e) {
        result.error = 'Script error: ' + e.message;
        result.debug += '\\nException: ' + e.stack;
    }

    return result;
    """
}
