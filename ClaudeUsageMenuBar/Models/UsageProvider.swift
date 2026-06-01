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

// Diagnostics-first: the authenticated Codex analytics page can't be browsed from
// the dev environment, so this is a best-effort extractor (progressbars + "% used"
// + reset regex) returning the same result-dict shape as the Claude script. Refine
// the selectors from the real "Show Debug Info" JSON after first Codex login.
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

    const parsePercentage = (value) => {
        if (value === null || value === undefined) return null;
        const m = String(value).match(/(\\d+(?:\\.\\d+)?)/);
        return m ? Math.round(Number(m[1])) : null;
    };

    const getProgressPercentage = (pb) => {
        const now = parsePercentage(pb.getAttribute('aria-valuenow'));
        if (now !== null) return now;
        const txt = parsePercentage(pb.getAttribute('aria-valuetext'));
        if (txt !== null) return txt;
        const fill = Array.from(pb.children).find(c => c.style && c.style.width);
        return fill ? parsePercentage(fill.style.width) : null;
    };

    const findResetText = (texts) => {
        const startsWithReset = texts.find(t => /^resets?\\b/i.test(t));
        if (startsWithReset) return startsWithReset;
        return texts.find(t => /\\b\\d+\\s*(?:days?|d|hours?|hrs?|hr|h|minutes?|mins?|min)\\b/i.test(t)) || null;
    };

    const pageHasUsage = () => {
        const t = document.body.innerText || '';
        return /%\\s*used/i.test(t) || document.querySelector('[role="progressbar"]') !== null;
    };

    try {
        for (let i = 0; i < 60; i++) {
            if (pageHasUsage()) break;
            await sleep(250);
        }

        const bodyText = document.body.innerText || '';
        const allTexts = Array.from(document.querySelectorAll('span,p,div,h1,h2,h3,h4'))
            .map(el => normalizeText(el.textContent))
            .filter(t => t && t.length <= 180);

        const percentMatches = [...bodyText.matchAll(/(\\d+(?:\\.\\d+)?)\\s*%\\s*used/gi)];
        if (percentMatches.length > 0) {
            result.percentage = Math.round(Number(percentMatches[0][1]));
            if (percentMatches[1]) result.weeklyPercentage = Math.round(Number(percentMatches[1][1]));
            logs.push(`Found ${percentMatches.length} "% used" matches`);
        }

        const progressbars = Array.from(document.querySelectorAll('[role="progressbar"]'));
        if (result.percentage === null && progressbars.length > 0) {
            const ordered = progressbars.map(getProgressPercentage).filter(p => p !== null);
            if (ordered[0] !== undefined) result.percentage = ordered[0];
            if (ordered[1] !== undefined) result.weeklyPercentage = ordered[1];
            logs.push(`Used ${ordered.length} progressbars in document order`);
        }

        result.resetTime = findResetText(allTexts);

        const emailMatch = bodyText.match(/[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}/i);
        if (emailMatch) result.email = emailMatch[0];
        const planMatch = bodyText.match(/\\b(Plus|Pro|Team|Enterprise|Business|Free)\\b/);
        if (planMatch) result.planName = planMatch[0];

        const progressbarDiagnostics = progressbars.slice(0, 10).map((pb, i) => ({
            index: i,
            ariaValueNow: pb.getAttribute('aria-valuenow'),
            ariaValueText: pb.getAttribute('aria-valuetext'),
            ariaLabel: pb.getAttribute('aria-label'),
            nearbyText: normalizeText(pb.parentElement?.parentElement?.textContent || '').substring(0, 200)
        }));
        const headingDiagnostics = Array.from(document.querySelectorAll('h1,h2,h3,h4'))
            .map(h => normalizeText(h.textContent)).filter(Boolean).slice(0, 30);
        const percentUsedMatches = [...bodyText.matchAll(/[^\\n]{0,40}\\d+\\s*%\\s*used[^\\n]{0,40}/gi)]
            .map(m => normalizeText(m[0])).slice(0, 10);

        result.debug = JSON.stringify({
            percentage: result.percentage,
            weeklyPercentage: result.weeklyPercentage,
            resetTime: result.resetTime,
            email: result.email,
            planName: result.planName,
            progressbarCount: progressbars.length,
            progressbars: progressbarDiagnostics,
            headings: headingDiagnostics,
            percentUsedMatches,
            logs,
            url: location.href
        }, null, 2);

        result.success = result.percentage !== null || result.email !== null;
        if (!result.success) result.error = 'No Codex usage found. Logs: ' + logs.join(' | ');
    } catch (e) {
        result.error = 'Script error: ' + e.message;
        result.debug += '\\nException: ' + e.stack;
    }

    return result;
    """
}
