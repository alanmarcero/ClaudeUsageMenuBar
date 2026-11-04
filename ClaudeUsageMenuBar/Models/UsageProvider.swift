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
    let primaryLabel: String       // row title for the primary (percentage) limit
    let secondaryLabel: String?    // row title for the secondary limit; nil hides that row
    let weeklyBlocksPrimary: Bool  // a spent secondary limit also blocks the primary one

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
        readsClaudeCodeLogin: true,
        primaryLabel: "Daily",
        secondaryLabel: "Weekly",
        weeklyBlocksPrimary: true
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
        readsClaudeCodeLogin: false,
        primaryLabel: "Daily",
        secondaryLabel: "Weekly",
        weeklyBlocksPrimary: true
    )

    static let cursor = UsageProvider(
        id: "cursor",
        displayName: "Cursor",
        menuGlyph: "cursorarrow.rays",
        primaryHost: "cursor.com",
        usageURL: URL(string: "https://cursor.com/dashboard/spending")!,
        usagePathFragment: "/dashboard/spending",
        loginPaths: ["/login", "/signin", "/auth"],
        oauthHostSuffixes: ["cursor.com", "cursor.sh", "workos.com", "github.com"] + sharedSSOHosts,
        dataRecordTokens: ["cursor"],
        scrapingScript: CursorScrapingScript.script,
        readsClaudeCodeLogin: false,
        primaryLabel: "Included",
        secondaryLabel: "Other Models",
        // Cursor's pools are independent: a spent Other Models pool does not
        // block Cursor Models, so neither pool reads as the other one.
        weeklyBlocksPrimary: false
    )

    // Grok Bot is Cursor's bot product ("Sand" on the wire): its weekly pool is
    // metered on the Cursor account, so it shares the Cursor login and session.
    static let grokBot = UsageProvider(
        id: "grokbot",
        displayName: "Grok Bot",
        menuGlyph: "sparkles",
        primaryHost: "cursor.com",
        usageURL: URL(string: "https://cursor.com/dashboard/bot")!,
        usagePathFragment: "/dashboard/bot",
        loginPaths: ["/login", "/signin", "/auth"],
        oauthHostSuffixes: ["cursor.com", "cursor.sh", "workos.com", "github.com"] + sharedSSOHosts,
        dataRecordTokens: ["cursor"],
        scrapingScript: GrokBotScrapingScript.script,
        readsClaudeCodeLogin: false,
        primaryLabel: "Weekly",
        secondaryLabel: nil,
        weeklyBlocksPrimary: false
    )

    static let all: [UsageProvider] = [.claude, .codex, .cursor, .grokBot]
}

// MARK: - Reset Details JavaScript

// The row of a reset button is its closest parent with "Expires" text and no other reset button.
// The script that includes this must define normalizeText.
enum ResetDetailsScript {
    static let describeResets = """
    const describeResets = (buttons) => buttons.map(button => {
        let row = button.parentElement;
        while (row && row !== document.body && !/Expires\\s/.test(row.textContent)) row = row.parentElement;
        if (!row || row === document.body || buttons.some(other => other !== button && row.contains(other))) {
            return { title: null, expires: null };
        }
        const walker = document.createTreeWalker(row, NodeFilter.SHOW_TEXT);
        const parts = [];
        while (walker.nextNode()) if (!button.contains(walker.currentNode)) parts.push(walker.currentNode.textContent);
        const match = normalizeText(parts.join(' ')).match(/^(.*?)\\s*\\bExpires\\s+(.+)$/);
        return { title: match?.[1] || null, expires: match?.[2] || null };
    });
    """
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
    \(ResetDetailsScript.describeResets)

    let buttons = resetButtons();
    for (let i = 0; i < 40 && buttons.length === 0; i++) {
        await new Promise(r => setTimeout(r, 250));
        buttons = resetButtons();
    }
    const resets = describeResets(buttons);

    return {
        availableResets: buttons.length,
        resets,
        debug: JSON.stringify({
            availableResets: buttons.length,
            buttonTexts: buttons.map(el => normalizeText(el.textContent)),
            resets,
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
        resets: [],
        creditsUsed: null,
        creditsLimit: null,
        error: null,
        debug: ''
    };

    const sleep = (ms) => new Promise(r => setTimeout(r, ms));
    const logs = [];
    const normalizeText = (v) => (v || '').replace(/\\s+/g, ' ').trim();
    // Apostrophe-agnostic: matches "couldn't"/"couldn’t"/"couldnt load your usage".
    const hasLoadError = (t) => /could.{0,3}t load your usage/i.test(t);
    \(ResetDetailsScript.describeResets)

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
        result.resets = describeResets(Array.from(document.querySelectorAll('button,[role="button"]'))
            .filter(el => /^use reset$/i.test(normalizeText(el.textContent))));

        // The usage API reports the credit limit. It needs the session's access token.
        const readCredits = async () => {
            try {
                const session = await (await fetch('/api/auth/session')).json();
                if (!session.accessToken) return 'no access token';
                const headers = { Authorization: `Bearer ${session.accessToken}` };
                if (session.account?.id) headers['ChatGPT-Account-Id'] = session.account.id;
                const response = await fetch('/backend-api/wham/usage', { headers });
                if (!response.ok) return `HTTP ${response.status}`;
                const limit = (await response.json()).spend_control?.individual_limit;
                if (limit?.unit !== 'credit') return 'no credit limit';
                const used = Number(limit.used);
                const creditLimit = Number(limit.limit);
                // A 0 limit means no credits are available. NaN crashes the Int conversion in Swift.
                if (!Number.isFinite(used) || !Number.isFinite(creditLimit) || creditLimit <= 0) return 'no usable credit limit';
                result.creditsUsed = used;
                result.creditsLimit = creditLimit;
                return 'ok';
            } catch (e) {
                return 'error: ' + e.message;
            }
        };
        const creditsStatus = await readCredits();
        logs.push(`Credits: ${creditsStatus}`);

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
            resets: result.resets,
            creditsUsed: result.creditsUsed,
            creditsLimit: result.creditsLimit,
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

// MARK: - Cursor JavaScript Scraping Script

// Cursor's dashboard is fed by GET /api/usage-summary, which the signed-in page
// can call same-origin (its session cookie is httpOnly but rides along). That
// response carries both pools: autoPercentUsed is the Cursor Models pool and
// apiPercentUsed the Other Models pool, while used/limit is the included total.
// Field mapping onto the shared model: included total -> percentage,
// Other Models -> weeklyPercentage, Cursor Models -> sonnetWeeklyPercentage
// with the full row title in sonnetWeeklyLabel. All three reset when the
// billing cycle ends. If the API ever stops answering, the Spending page's
// pool labels are scraped as a fallback.
enum CursorScrapingScript {
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
        sonnetWeeklyLabel: null,
        designWeeklyLabel: null,
        email: null,
        orgName: null,
        planName: null,
        availableResets: null,
        resets: [],
        creditsUsed: null,
        creditsLimit: null,
        onDemandUsed: null,
        teamOnDemandUsed: null,
        teamOnDemandLimit: null,
        error: null,
        debug: ''
    };

    const sleep = (ms) => new Promise(r => setTimeout(r, ms));
    const logs = [];
    const normalizeText = (v) => (v || '').replace(/\\s+/g, ' ').trim();
    const roundPct = (v) => {
        const n = Number(v);
        return v === null || v === undefined || !Number.isFinite(n) ? null : Math.round(n);
    };
    // The summary reports money in cents.
    const centsToDollars = (v) => {
        if (v === null || v === undefined) return null;
        const n = Number(v);
        return Number.isFinite(n) ? n / 100 : null;
    };

    const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const formatReset = (value) => {
        if (value === null || value === undefined || value === '') return null;
        const date = new Date(typeof value === 'string' && /^\\d+$/.test(value) ? Number(value) : value);
        if (isNaN(date.getTime())) return null;
        let hour = date.getHours();
        const ampm = hour >= 12 ? 'PM' : 'AM';
        hour = hour % 12 || 12;
        const minute = String(date.getMinutes()).padStart(2, '0');
        return `Resets ${monthNames[date.getMonth()]} ${date.getDate()}, ${date.getFullYear()} ${hour}:${minute} ${ampm}`;
    };

    const planDisplayName = (membershipType) => {
        if (!membershipType) return null;
        return String(membershipType).replace(/_/g, ' ').replace(/\\b\\w/g, c => c.toUpperCase());
    };

    const readUsageSummary = async () => {
        try {
            const response = await fetch('/api/usage-summary', { credentials: 'include', headers: { Accept: 'application/json' } });
            if (response.status === 401 || response.status === 403) return { status: 'unauthenticated' };
            if (!response.ok) return { status: `HTTP ${response.status}` };
            return { status: 'ok', data: await response.json() };
        } catch (e) {
            return { status: 'error: ' + e.message };
        }
    };

    const applySummary = (data) => {
        const plan = data?.individualUsage?.plan;
        if (!plan) return false;
        const reset = formatReset(data.billingCycleEnd);
        const used = Number(plan.used);
        const limit = Number(plan.limit);
        result.percentage = limit > 0 && Number.isFinite(used)
            ? Math.round(used / limit * 100)
            : roundPct(plan.totalPercentUsed);
        result.resetTime = reset;
        result.weeklyPercentage = roundPct(plan.apiPercentUsed);
        result.weeklyResetTime = reset;
        result.sonnetWeeklyPercentage = roundPct(plan.autoPercentUsed);
        result.sonnetWeeklyResetTime = reset;
        if (result.sonnetWeeklyPercentage !== null) result.sonnetWeeklyLabel = 'Cursor Models';
        result.planName = planDisplayName(data.membershipType);
        // On-demand spend draws on the team budget once included usage is gone.
        result.onDemandUsed = centsToDollars(data?.individualUsage?.onDemand?.used);
        result.teamOnDemandUsed = centsToDollars(data?.teamUsage?.onDemand?.used);
        const teamLimit = centsToDollars(data?.teamUsage?.onDemand?.limit);
        result.teamOnDemandLimit = teamLimit !== null && teamLimit > 0 ? teamLimit : null;
        return result.percentage !== null || result.weeklyPercentage !== null || result.sonnetWeeklyPercentage !== null;
    };

    const findPoolPercentage = (labelPattern) => {
        const labels = Array.from(document.querySelectorAll('span,p,div,h1,h2,h3,h4'))
            .filter(el => labelPattern.test(normalizeText(el.textContent)));
        for (const label of labels) {
            for (let container = label.parentElement; container && container !== document.body; container = container.parentElement) {
                const text = normalizeText(container.textContent);
                if (text.length > 300) break;
                const match = text.match(/(\\d+(?:\\.\\d+)?)\\s*%\\s*used/i) || text.match(/(\\d+(?:\\.\\d+)?)\\s*%/);
                if (match) return Math.round(Number(match[1]));
            }
        }
        return null;
    };

    try {
        const summary = await readUsageSummary();
        logs.push(`usage-summary: ${summary.status}`);

        if (summary.status === 'unauthenticated') {
            result.error = 'Click the person icon next to Cursor to log in.';
        } else if (!(summary.data && applySummary(summary.data))) {
            for (let i = 0; i < 40; i++) {        // up to 10s for the pools to render
                result.sonnetWeeklyPercentage = findPoolPercentage(/cursor models/i);
                result.weeklyPercentage = findPoolPercentage(/other models/i);
                if (result.sonnetWeeklyPercentage !== null || result.weeklyPercentage !== null) break;
                await sleep(250);
            }
            if (result.sonnetWeeklyPercentage !== null) result.sonnetWeeklyLabel = 'Cursor Models';
            logs.push(`DOM fallback: Cursor Models=${result.sonnetWeeklyPercentage}, Other Models=${result.weeklyPercentage}`);
        }

        const bodyText = normalizeText(document.body?.innerText || document.body?.textContent || '');
        const emailMatch = bodyText.match(/[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}/i);
        if (emailMatch) result.email = emailMatch[0];
        if (!result.planName) {
            const planMatch = bodyText.match(/\\b(Pro Plus|Pro\\+|Ultra|Enterprise|Teams|Pro|Hobby|Free)\\b/);
            if (planMatch) result.planName = planMatch[1];
        }

        result.debug = JSON.stringify({
            percentage: result.percentage,
            weeklyPercentage: result.weeklyPercentage,
            sonnetWeeklyPercentage: result.sonnetWeeklyPercentage,
            resetTime: result.resetTime,
            planName: result.planName,
            email: result.email,
            onDemandUsed: result.onDemandUsed,
            teamOnDemandUsed: result.teamOnDemandUsed,
            teamOnDemandLimit: result.teamOnDemandLimit,
            summaryStatus: summary.status,
            logs,
            bodyTextSnippet: bodyText.substring(0, 2000),
            url: location.href
        }, null, 2);

        result.success = result.percentage !== null || result.weeklyPercentage !== null || result.sonnetWeeklyPercentage !== null;
        if (!result.success && !result.error) {
            result.error = 'No Cursor usage parsed yet. See bodyTextSnippet in debug.';
        }
    } catch (e) {
        result.error = 'Script error: ' + e.message;
        result.debug += '\\nException: ' + e.stack;
    }

    return result;
    """
}

// MARK: - Grok Bot JavaScript Scraping Script

// Grok Bot ("Sand") usage is metered on the Cursor account. The dashboard's
// POST /api/dashboard/get-sand-usage-status reports the weekly included pool:
// usagePercent used, nextResetTimestampUtc, and flags that say whether the
// plan includes a pool at all — an account without one also answers 0%, so
// hasNonZeroIncludedLimit must be checked before trusting the percentage.
// Keys arrive camelCase; the proto (snake_case) spellings are accepted too.
enum GrokBotScrapingScript {
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
        sonnetWeeklyLabel: null,
        designWeeklyLabel: null,
        email: null,
        orgName: null,
        planName: null,
        availableResets: null,
        resets: [],
        creditsUsed: null,
        creditsLimit: null,
        error: null,
        debug: ''
    };

    const logs = [];
    const normalizeText = (v) => (v || '').replace(/\\s+/g, ' ').trim();
    const pick = (obj, camel, snake) => obj?.[camel] ?? obj?.[snake];
    const roundPct = (v) => {
        const n = Number(v);
        return v === null || v === undefined || !Number.isFinite(n) ? null : Math.round(n);
    };

    const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const formatReset = (value) => {
        if (value === null || value === undefined || value === '') return null;
        const date = new Date(typeof value === 'string' && /^\\d+$/.test(value) ? Number(value) : value);
        if (isNaN(date.getTime())) return null;
        let hour = date.getHours();
        const ampm = hour >= 12 ? 'PM' : 'AM';
        hour = hour % 12 || 12;
        const minute = String(date.getMinutes()).padStart(2, '0');
        return `Resets ${monthNames[date.getMonth()]} ${date.getDate()}, ${date.getFullYear()} ${hour}:${minute} ${ampm}`;
    };

    const readSandUsageStatus = async () => {
        try {
            const response = await fetch('/api/dashboard/get-sand-usage-status', {
                method: 'POST',
                credentials: 'include',
                headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
                body: '{}'
            });
            if (response.status === 401 || response.status === 403) return { status: 'unauthenticated' };
            if (!response.ok) return { status: `HTTP ${response.status}` };
            return { status: 'ok', data: await response.json() };
        } catch (e) {
            return { status: 'error: ' + e.message };
        }
    };

    try {
        const sand = await readSandUsageStatus();
        logs.push(`get-sand-usage-status: ${sand.status}`);

        if (sand.status === 'unauthenticated') {
            result.error = 'Click the person icon next to Grok Bot to log in.';
        } else if (sand.data) {
            const data = sand.data;
            const usagePercent = roundPct(pick(data, 'usagePercent', 'usage_percent'));
            const hasLimit = pick(data, 'hasNonZeroIncludedLimit', 'has_non_zero_included_limit');
            const limitZero = pick(data, 'includedLimitZero', 'included_limit_zero');
            if (hasLimit === false || limitZero === true) {
                result.error = 'Your plan does not include Grok Bot usage.';
            } else if (usagePercent !== null) {
                result.percentage = usagePercent;
                result.resetTime = formatReset(pick(data, 'nextResetTimestampUtc', 'next_reset_timestamp_utc'));
                result.planName = pick(data, 'cursorPlanName', 'cursor_plan_name')
                    ?? pick(data, 'grokPlanLabel', 'grok_plan_label')
                    ?? null;
            }
            logs.push(`usagePercent=${usagePercent}, hasNonZeroIncludedLimit=${hasLimit}, includedLimitZero=${limitZero}`);
        }

        const bodyText = normalizeText(document.body?.innerText || document.body?.textContent || '');
        const emailMatch = bodyText.match(/[a-z0-9._%+-]+@[a-z0-9.-]+\\.[a-z]{2,}/i);
        if (emailMatch) result.email = emailMatch[0];

        result.debug = JSON.stringify({
            percentage: result.percentage,
            resetTime: result.resetTime,
            planName: result.planName,
            email: result.email,
            sandStatus: sand.status,
            logs,
            bodyTextSnippet: bodyText.substring(0, 2000),
            url: location.href
        }, null, 2);

        result.success = result.percentage !== null;
        if (!result.success && !result.error) {
            result.error = 'No Grok Bot usage parsed yet. See bodyTextSnippet in debug.';
        }
    } catch (e) {
        result.error = 'Script error: ' + e.message;
        result.debug += '\\nException: ' + e.stack;
    }

    return result;
    """
}
