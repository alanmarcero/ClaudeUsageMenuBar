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
        scrapingScript: UsageScrapingScript.script
    )

    static let codex = UsageProvider(
        id: "codex",
        displayName: "Codex",
        menuGlyph: "chevron.left.forwardslash.chevron.right",
        primaryHost: "chatgpt.com",
        usageURL: URL(string: "https://chatgpt.com/codex/cloud/settings/analytics")!,
        usagePathFragment: "/codex/cloud/settings/analytics",
        loginPaths: ["/login", "/auth/login", "/auth"],
        oauthHostSuffixes: ["chatgpt.com", "openai.com", "oaistatic.com", "oaiusercontent.com"] + sharedSSOHosts,
        dataRecordTokens: ["openai", "chatgpt", "oaistatic"],
        scrapingScript: CodexScrapingScript.script
    )

    static let all: [UsageProvider] = [.claude, .codex]
}

// MARK: - Codex JavaScript Scraping Script

// Diagnostics-first: the Codex analytics page renders a "Balance" / "Usage breakdown"
// layout (not Claude's progressbar/"% used" pattern) and can transiently show
// "We couldn't load your usage" before its data fetch settles. This script retries
// past that error state, attempts percentage/"X / Y" extraction, and dumps the page's
// visible text + numeric tokens so the selectors can be tightened from real output.
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
        error: null,
        debug: ''
    };

    const sleep = (ms) => new Promise(r => setTimeout(r, ms));
    const logs = [];
    const normalizeText = (v) => (v || '').replace(/\\s+/g, ' ').trim();
    // Apostrophe-agnostic: matches "couldn't"/"couldn’t"/"couldnt load your usage".
    const hasLoadError = (t) => /could.{0,3}t load your usage/i.test(t);

    const bodyTextNow = () => normalizeText(document.body.innerText || document.body.textContent || '');

    const pageSettled = () => {
        const t = bodyTextNow().toLowerCase();
        if (hasLoadError(t)) return false;
        return /%/.test(t) || /\\$\\s*\\d/.test(t) || /\\d+\\s*\\/\\s*\\d+/.test(t) || t.includes('balance');
    };

    const parsePercentage = (value) => {
        if (value === null || value === undefined) return null;
        const m = String(value).match(/(\\d+(?:\\.\\d+)?)/);
        return m ? Math.round(Number(m[1])) : null;
    };

    const findResetText = (texts) => {
        const startsWithReset = texts.find(t => /^resets?\\b/i.test(t));
        if (startsWithReset) return startsWithReset;
        return texts.find(t => /\\b\\d+\\s*(?:days?|d|hours?|hrs?|hr|h|minutes?|mins?|min)\\b/i.test(t)) || null;
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

        // Codex reports "<label> N% remaining"; Claude (and this app) display % USED,
        // so invert: used = 100 - remaining. "5 hour usage limit" -> daily, "Weekly
        // usage limit" -> weekly.
        const toUsed = (remaining) => Math.round(100 - Number(remaining));

        const dailyMatch = bodyText.match(/5\\s*hour usage limit\\s*(\\d+(?:\\.\\d+)?)\\s*%\\s*remaining/i);
        if (dailyMatch) {
            result.percentage = toUsed(dailyMatch[1]);
            logs.push(`Daily ${dailyMatch[1]}% remaining -> ${result.percentage}% used`);
        }

        const weeklyMatch = bodyText.match(/weekly usage limit\\s*(\\d+(?:\\.\\d+)?)\\s*%\\s*remaining/i);
        if (weeklyMatch) {
            result.weeklyPercentage = toUsed(weeklyMatch[1]);
            logs.push(`Weekly ${weeklyMatch[1]}% remaining -> ${result.weeklyPercentage}% used`);
        }

        // Fallbacks if the labels change: invert any "% remaining", else take "% used".
        if (result.percentage === null) {
            const remaining = bodyText.match(/(\\d+(?:\\.\\d+)?)\\s*%\\s*remaining/i);
            const used = bodyText.match(/(\\d+(?:\\.\\d+)?)\\s*%\\s*used/i);
            if (remaining) result.percentage = toUsed(remaining[1]);
            else if (used) result.percentage = Math.round(Number(used[1]));
        }

        const resetMatch = bodyText.match(/Resets\\s+(\\d{1,2}:\\d{2}\\s*(?:AM|PM)?)/i);
        result.resetTime = resetMatch ? ('Resets ' + resetMatch[1]) : findResetText(allTexts);

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
            email: result.email,
            planName: result.planName,
            sawLoadError,
            pageSettled: pageSettled(),
            progressbarCount: progressbars.length,
            headings: headingDiagnostics,
            valueTokens,
            bodyTextSnippet: bodyText.substring(0, 3000),
            logs,
            url: location.href
        }, null, 2);

        result.success = result.percentage !== null || result.email !== null;
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
