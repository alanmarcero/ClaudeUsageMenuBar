import Foundation

// A provider descriptor fully describes a usage source (URL, glyph, OAuth hosts,
// scraping script), so the rest of the app stays provider-agnostic. Adding a
// provider means adding a descriptor and a scraping script — no code forks.
struct UsageProvider: Identifiable {
    let id: String
    let displayName: String
    let menuGlyph: String          // SF Symbol
    let primaryHost: String        // host whose non-usage pages redirect to usageURL
    let usageURL: URL
    let usagePathFragment: String
    let loginPaths: [String]
    let oauthHostSuffixes: [String]
    let dataRecordTokens: [String] // WKWebsiteDataStore display-name tokens cleared on logout
    let scrapingScript: String
    let readsClaudeCodeLogin: Bool // prefer Claude Code's saved login over the web page

    static let sharedSSOHosts = [
        "google.com", "googleapis.com", "gstatic.com",
        "apple.com", "icloud.com",
        "microsoftonline.com", "microsoft.com", "live.com",
        "okta.com", "auth0.com",
        "clerk.dev", "clerk.accounts.dev"
    ]

    static let claude = UsageProvider(
        id: "claude",
        displayName: "Claude",
        menuGlyph: "cpu.fill",
        primaryHost: "claude.ai",
        usageURL: URL(string: "https://claude.ai/settings/usage")!,
        usagePathFragment: "/settings/usage",
        loginPaths: ["/login", "/signin"],
        oauthHostSuffixes: ["claude.ai", "anthropic.com"] + sharedSSOHosts,
        dataRecordTokens: ["claude", "anthropic"],
        scrapingScript: UsageScrapingScript.script,
        readsClaudeCodeLogin: true
    )

    static let codex = UsageProvider(
        id: "codex",
        displayName: "Codex",
        menuGlyph: "chevron.left.forwardslash.chevron.right",
        primaryHost: "chatgpt.com",
        usageURL: URL(string: "https://chatgpt.com/settings/usage")!,
        // chatgpt.com can redirect the usage page to "/?mweb_fallback=1#settings/usage".
        usagePathFragment: "settings/usage",
        loginPaths: ["/login", "/auth/login", "/auth"],
        oauthHostSuffixes: ["chatgpt.com", "openai.com", "oaistatic.com", "oaiusercontent.com"] + sharedSSOHosts,
        dataRecordTokens: ["openai", "chatgpt", "oaistatic"],
        scrapingScript: CodexScrapingScript.script,
        readsClaudeCodeLogin: false
    )

    static let all: [UsageProvider] = [.claude, .codex]
}

// MARK: - Claude Resets JavaScript Script

// Counts the reset buttons on the claude.ai usage page, e.g. "Reset for free".
// The buttons can render after the usage bars, so it waits up to 10s for one.
enum ClaudeResetsScript {
    static let script = """
    const resetButtonPattern = /^(reset for free|use reset|reset now|reset)$/i;
    const normalizeText = (v) => (v || '').replace(/\\s+/g, ' ').trim();
    const resetButtons = () => Array.from(document.querySelectorAll('button,[role="button"]'))
        .filter(el => resetButtonPattern.test(normalizeText(el.textContent)));

    let buttons = resetButtons();
    for (let i = 0; i < 40 && buttons.length === 0; i++) {
        await new Promise(r => setTimeout(r, 250));
        buttons = resetButtons();
    }

    return {
        availableResets: buttons.length,
        debug: JSON.stringify({
            availableResets: buttons.length,
            buttonTexts: buttons.map(el => normalizeText(el.textContent)),
            url: location.href
        })
    };
    """
}

// MARK: - Codex JavaScript Scraping Script

enum CodexScrapingScript {
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
        availableResets: null,
        error: null,
        debug: ''
    };

    const sleep = (ms) => new Promise(r => setTimeout(r, ms));
    const logs = [];
    const normalizeText = (v) => (v || '').replace(/\\s+/g, ' ').trim();
    // Apostrophe-agnostic: matches "couldn't"/"couldn’t"/"couldnt load your usage".
    const hasLoadError = (t) => /could.{0,3}t load your usage/i.test(t);

    const bodyTextNow = () => normalizeText(document.body.innerText || document.body.textContent || '');

    const dailyLabelPattern = /^5\\s*(?:-|–)?\\s*hour (?:usage )?limit$/i;
    const weeklyLabelPattern = /^weekly (?:usage )?limit$/i;
    const remainingPattern = /(\\d+(?:\\.\\d+)?)\\s*%\\s*(?:remaining|left)\\b/i;

    const findLimitSection = (labelPattern) => {
        const labels = Array.from(document.querySelectorAll('span,p,div,h1,h2,h3,h4'))
            .filter(el => {
                const text = normalizeText(el.textContent);
                return dailyLabelPattern.test(text) || weeklyLabelPattern.test(text);
            });
        for (const label of labels.filter(el => labelPattern.test(normalizeText(el.textContent)))) {
            for (let container = label.parentElement; container && container !== document.body; container = container.parentElement) {
                if (labels.some(other => container.contains(other) && !labelPattern.test(normalizeText(other.textContent)))) break;
                const walker = document.createTreeWalker(container, NodeFilter.SHOW_TEXT);
                const parts = [];
                while (walker.nextNode()) parts.push(walker.currentNode.textContent);
                const section = normalizeText(parts.join(' '));
                if (remainingPattern.test(section)) return section;
            }
        }
        return null;
    };

    const pageSettled = () => {
        if (hasLoadError(bodyTextNow())) return false;
        return findLimitSection(dailyLabelPattern) !== null || findLimitSection(weeklyLabelPattern) !== null;
    };

    try {
        let sawLoadError = false;
        for (let i = 0; i < 80; i++) {            // up to 20s
            if (hasLoadError(bodyTextNow())) sawLoadError = true;
            if (pageSettled()) break;
            await sleep(250);
        }
        if (sawLoadError) logs.push('Encountered load-error state while polling');

        const bodyText = bodyTextNow();
        const allTexts = Array.from(document.querySelectorAll('span,p,div,h1,h2,h3,h4,li,td,th'))
            .map(el => normalizeText(el.textContent))
            .filter(t => t && t.length <= 120);

        // Candidate value tokens: anything with a %, $, "X / Y", or usage/credit/balance keyword.
        const valueTokens = [...new Set(allTexts.filter(t =>
            /\\d+\\s*%/.test(t) ||
            /\\$\\s*\\d/.test(t) ||
            /\\d+\\s*\\/\\s*\\d+/.test(t) ||
            /\\b(used|remaining|balance|credit|credits|limit|quota|reset)\\b/i.test(t)
        ))].slice(0, 40);

        const findResetForLimit = (section) => {
            // Match only a real reset timestamp. A broad wildcard here used to start at
            // explanatory copy such as "Resets — Use a reset to restore your..." and
            // consume everything through a later timestamp.
            const clockReset = section.match(/\\bresets?\\s+(?:(?:Sun(?:day)?|Mon(?:day)?|Tue(?:sday)?|Wed(?:nesday)?|Thu(?:rsday)?|Fri(?:day)?|Sat(?:urday)?)\\s+|(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\\s+\\d{1,2},\\s*\\d{4}(?:\\s+at)?\\s+)?\\d{1,2}:\\d{2}\\s*(?:AM|PM)\\b/i);
            if (clockReset) return normalizeText(clockReset[0]);

            const relativeReset = section.match(/\\bresets?\\s+(?:in\\s+)?\\d+\\s*(?:days?|d|hours?|hrs?|hr|h|minutes?|mins?|min|m)(?:\\s+\\d+\\s*(?:days?|d|hours?|hrs?|hr|h|minutes?|mins?|min|m)){0,2}/i);
            return relativeReset ? normalizeText(relativeReset[0]) : null;
        };

        const dailySection = findLimitSection(dailyLabelPattern);
        if (dailySection) {
            const remaining = dailySection.match(remainingPattern)[1];
            result.percentage = Math.round(100 - Number(remaining));
            result.resetTime = findResetForLimit(dailySection);
            logs.push(`Daily ${remaining}% remaining -> ${result.percentage}% used`);
        }

        const weeklySection = findLimitSection(weeklyLabelPattern);
        if (weeklySection) {
            const remaining = weeklySection.match(remainingPattern)[1];
            result.weeklyPercentage = Math.round(100 - Number(remaining));
            result.weeklyResetTime = findResetForLimit(weeklySection);
            logs.push(`Weekly ${remaining}% remaining -> ${result.weeklyPercentage}% used`);
        }

        // Each available reset has its own "Use reset" button. Skip script and style
        // text: the page bundles its UI strings there.
        const countAvailableResets = () => {
            const resetsWalker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
                acceptNode: (node) => /^(SCRIPT|STYLE)$/.test(node.parentElement?.tagName ?? '')
                    ? NodeFilter.FILTER_REJECT
                    : NodeFilter.FILTER_ACCEPT
            });
            const pageTextParts = [];
            while (resetsWalker.nextNode()) pageTextParts.push(resetsWalker.currentNode.textContent);
            const pageText = normalizeText(pageTextParts.join(' '));
            if (!/usage limit resets/i.test(pageText)) return null;
            return (pageText.match(/\\buse reset\\b/gi) || []).length;
        };

        // The reset list can render after the limit cards. A count made too early
        // reads 0, so wait up to 5s for the buttons before accepting 0.
        result.availableResets = countAvailableResets();
        for (let i = 0; i < 20 && result.availableResets === 0; i++) {
            await sleep(250);
            result.availableResets = countAvailableResets();
        }
        if (result.availableResets !== null) logs.push(`Available resets: ${result.availableResets}`);

        const emailMatch = bodyText.match(/[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}/i);
        if (emailMatch) result.email = emailMatch[0];
        const planMatch = bodyText.match(/\\b(Plus|Pro|Team|Enterprise|Business|Free)\\b/);
        if (planMatch) result.planName = planMatch[0];

        const headingDiagnostics = Array.from(document.querySelectorAll('h1,h2,h3,h4'))
            .map(h => normalizeText(h.textContent)).filter(Boolean).slice(0, 40);
        const progressbars = Array.from(document.querySelectorAll('[role="progressbar"]'));

        result.debug = JSON.stringify({
            percentage: result.percentage,
            weeklyPercentage: result.weeklyPercentage,
            resetTime: result.resetTime,
            weeklyResetTime: result.weeklyResetTime,
            email: result.email,
            planName: result.planName,
            availableResets: result.availableResets,
            sawLoadError,
            pageSettled: pageSettled(),
            progressbarCount: progressbars.length,
            headings: headingDiagnostics,
            valueTokens,
            bodyTextSnippet: bodyText.substring(0, 3000),
            logs,
            url: location.href
        }, null, 2);

        result.success = result.percentage !== null || result.weeklyPercentage !== null || result.email !== null;
        if (!result.success) {
            result.error = sawLoadError
                ? 'Codex reported it could not load usage right now. Will retry automatically.'
                : 'No Codex usage parsed yet. See valueTokens/bodyTextSnippet in debug.';
        }
    } catch (e) {
        result.error = 'Script error: ' + e.message;
        result.debug += '\\nException: ' + e.stack;
    }

    return result;
    """
}
