import XCTest
import WebKit
@testable import ClaudeUsageMenuBar

final class UsageProviderTests: XCTestCase {

    func testRegistryContainsClaudeAndCodex() {
        let ids = UsageProvider.all.map { $0.id }
        XCTAssertEqual(ids, ["claude", "codex", "cursor", "grokbot"])
    }

    @MainActor
    func testProvidersStartAllVisible() {
        let container = UsageProviders(providers: [.claude, .codex], defaults: makeSuiteDefaults().defaults)
        XCTAssertEqual(container.visibleServices.map { $0.provider.id }, ["claude", "codex"])
        XCTAssertTrue(container.hiddenProviderIDs.isEmpty)
    }

    @MainActor
    func testHidingProviderRemovesItPausesItAndPersists() {
        let (defaults, suite) = makeSuiteDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = UsageProviders(providers: [.claude, .codex], defaults: defaults)

        container.setProviderVisible(false, providerID: "codex")

        XCTAssertEqual(container.visibleServices.map { $0.provider.id }, ["claude"])
        XCTAssertFalse(container.isVisible("codex"))
        XCTAssertEqual(Set(defaults.stringArray(forKey: "hiddenProviderIDs") ?? []), ["codex"])
        XCTAssertTrue(container.services.first { $0.provider.id == "codex" }!.isRefreshPaused)

        // A fresh container on the same defaults restores the hidden set.
        let restored = UsageProviders(providers: [.claude, .codex], defaults: defaults)
        XCTAssertEqual(restored.visibleServices.map { $0.provider.id }, ["claude"])
    }

    @MainActor
    func testLastVisibleProviderCannotBeHidden() {
        let container = UsageProviders(providers: [.claude, .codex], defaults: makeSuiteDefaults().defaults)
        container.setProviderVisible(false, providerID: "codex")
        container.setProviderVisible(false, providerID: "claude")
        XCTAssertEqual(container.visibleServices.map { $0.provider.id }, ["claude"])
    }

    @MainActor
    func testHidingSelectedProviderMovesSelectionToAVisibleOne() {
        let container = UsageProviders(providers: [.claude, .codex], defaults: makeSuiteDefaults().defaults)
        XCTAssertEqual(container.selectedMenuBarProviderID, "claude")

        container.setProviderVisible(false, providerID: "claude")

        XCTAssertEqual(container.selectedMenuBarProviderID, "codex")
        XCTAssertEqual(container.selectedService?.provider.id, "codex")
    }

    @MainActor
    func testShowingProviderAgainUnpausesIt() {
        let container = UsageProviders(providers: [.claude, .codex], defaults: makeSuiteDefaults().defaults)
        container.setProviderVisible(false, providerID: "codex")
        container.setProviderVisible(true, providerID: "codex")

        XCTAssertEqual(container.visibleServices.map { $0.provider.id }, ["claude", "codex"])
        XCTAssertFalse(container.services.first { $0.provider.id == "codex" }!.isRefreshPaused)
    }

    @MainActor
    func testAllHiddenInDefaultsKeepsFirstProviderVisible() {
        let (defaults, suite) = makeSuiteDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["claude", "codex"], forKey: "hiddenProviderIDs")

        let container = UsageProviders(providers: [.claude, .codex], defaults: defaults)
        XCTAssertEqual(container.visibleServices.map { $0.provider.id }, ["claude"])
    }

    @MainActor
    func testCursorMenuBarMetricDefaultsToOtherModels() {
        let container = UsageProviders(providers: [.cursor], defaults: makeSuiteDefaults().defaults)
        let service = container.services[0]
        service.usageData.percentage = 10
        service.usageData.weeklyPercentage = 70
        // No Included metric: the default is the Other Models pool.
        XCTAssertEqual(container.cursorMenuBarMetricID, "other")
        XCTAssertEqual(container.menuBarDisplay(for: service), "70%")
        XCTAssertFalse(UsageProviders.cursorMetricOptions.contains { $0.id == "included" })
    }

    @MainActor
    func testSavedIncludedMetricMigratesToOtherModels() {
        let (defaults, suite) = makeSuiteDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("included", forKey: "cursorMenuBarMetricID")

        let container = UsageProviders(providers: [.cursor], defaults: defaults)
        XCTAssertEqual(container.cursorMenuBarMetricID, "other")
    }

    @MainActor
    func testCursorMenuBarMetricSelectsDisplaysAndPersists() {
        let (defaults, suite) = makeSuiteDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = UsageProviders(providers: [.claude, .cursor], defaults: defaults)
        let cursor = container.services.first { $0.provider.id == "cursor" }!
        cursor.usageData.percentage = 10
        cursor.usageData.weeklyPercentage = 70
        cursor.usageData.sonnetWeeklyPercentage = 30
        cursor.usageData.onDemandUsedDollars = 12.34

        container.setCursorMenuBarMetric("other")
        XCTAssertEqual(container.menuBarDisplay(for: cursor), "70%")
        // Picking a metric also selects Cursor for the menu bar.
        XCTAssertEqual(container.selectedMenuBarProviderID, "cursor")

        container.setCursorMenuBarMetric("cursor")
        XCTAssertEqual(container.menuBarDisplay(for: cursor), "30%")

        container.setCursorMenuBarMetric("ondemand")
        XCTAssertEqual(container.menuBarDisplay(for: cursor), "$12.34")

        container.setCursorMenuBarMetric("bogus")
        XCTAssertEqual(container.cursorMenuBarMetricID, "ondemand")

        let restored = UsageProviders(providers: [.claude, .cursor], defaults: defaults)
        XCTAssertEqual(restored.cursorMenuBarMetricID, "ondemand")
    }

    @MainActor
    func testGrokBotIsAMenuBarMetricButHasNoTopSelector() {
        let container = UsageProviders(providers: [.claude, .cursor, .grokBot], defaults: makeSuiteDefaults().defaults)
        let cursor = container.services.first { $0.provider.id == "cursor" }!
        let grok = container.services.first { $0.provider.id == "grokbot" }!
        cursor.usageData.percentage = 10
        grok.usageData.percentage = 55

        // No Grok Bot chip at the top, and no separate section while Cursor shows.
        XCTAssertEqual(container.selectorServices.map { $0.provider.id }, ["claude", "cursor"])
        XCTAssertEqual(container.sectionServices.map { $0.provider.id }, ["claude", "cursor"])

        container.setCursorMenuBarMetric("grokbot")
        XCTAssertEqual(container.menuBarDisplay(for: cursor), "55%")
        XCTAssertEqual(container.selectedMenuBarProviderID, "cursor")
    }

    @MainActor
    func testGrokBotSectionStandsAloneWhenCursorIsHidden() {
        let container = UsageProviders(providers: [.claude, .cursor, .grokBot], defaults: makeSuiteDefaults().defaults)
        container.setProviderVisible(false, providerID: "cursor")
        XCTAssertEqual(container.sectionServices.map { $0.provider.id }, ["claude", "grokbot"])
    }

    @MainActor
    func testSavedGrokBotSelectionBecomesCursor() {
        let (defaults, suite) = makeSuiteDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("grokbot", forKey: "menuBarProviderID")

        let container = UsageProviders(providers: [.claude, .cursor, .grokBot], defaults: defaults)
        XCTAssertEqual(container.selectedMenuBarProviderID, "cursor")
        XCTAssertEqual(container.selectedService?.provider.id, "cursor")
    }

    @MainActor
    func testHidingGrokBotFallsMenuBarMetricBackToOtherModels() {
        let container = UsageProviders(providers: [.claude, .cursor, .grokBot], defaults: makeSuiteDefaults().defaults)
        let cursor = container.services.first { $0.provider.id == "cursor" }!
        cursor.usageData.percentage = 10
        cursor.usageData.weeklyPercentage = 70
        container.setCursorMenuBarMetric("grokbot")

        container.setProviderVisible(false, providerID: "grokbot")

        XCTAssertEqual(container.cursorMenuBarMetricID, "other")
        XCTAssertEqual(container.menuBarDisplay(for: cursor), "70%")
    }

    @MainActor
    func testMenuBarDisplayIgnoresCursorMetricForOtherProviders() {
        let container = UsageProviders(providers: [.claude, .cursor], defaults: makeSuiteDefaults().defaults)
        let claude = container.services.first { $0.provider.id == "claude" }!
        claude.usageData.percentage = 45
        container.setCursorMenuBarMetric("other")
        XCTAssertEqual(container.menuBarDisplay(for: claude), "45%")
    }

    private func makeSuiteDefaults() -> (defaults: UserDefaults, suite: String) {
        let suite = "test-usageproviders-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    func testEachProviderHasNonEmptyScriptAndValidURL() {
        XCTAssertEqual(UsageProvider.all.count, 4)
        UsageProvider.all.forEach { provider in
            XCTAssertFalse(provider.scrapingScript.isEmpty, "\(provider.id) script empty")
            XCTAssertFalse(provider.usageURL.absoluteString.isEmpty, "\(provider.id) url empty")
            XCTAssertTrue(provider.usageURL.absoluteString.contains(provider.usagePathFragment), "\(provider.id) fragment")
        }
    }

    func testCodexFragmentMatchesHashRedirect() {
        XCTAssertTrue("https://chatgpt.com/?mweb_fallback=1#settings/usage".contains(UsageProvider.codex.usagePathFragment))
    }

    func testClaudeOAuthHostsIncludeSharedSSOAndOwnDomains() {
        let hosts = UsageProvider.claude.oauthHostSuffixes
        XCTAssertTrue(hosts.contains("claude.ai"))
        XCTAssertTrue(hosts.contains("anthropic.com"))
        XCTAssertTrue(hosts.contains("google.com"))
    }

    func testCodexOAuthHostsIncludeOpenAIAndSharedSSO() {
        let hosts = UsageProvider.codex.oauthHostSuffixes
        XCTAssertTrue(hosts.contains("chatgpt.com"))
        XCTAssertTrue(hosts.contains("openai.com"))
        XCTAssertTrue(hosts.contains("apple.com"))
    }

    func testCursorOAuthHostsIncludeCursorAuthAndSharedSSO() {
        let hosts = UsageProvider.cursor.oauthHostSuffixes
        XCTAssertTrue(hosts.contains("cursor.com"))
        XCTAssertTrue(hosts.contains("cursor.sh"))
        XCTAssertTrue(hosts.contains("workos.com"))
        XCTAssertTrue(hosts.contains("github.com"))
        XCTAssertTrue(hosts.contains("google.com"))
    }

    func testCursorRowLabelsAndIndependentPools() {
        XCTAssertEqual(UsageProvider.cursor.primaryLabel, "Included")
        XCTAssertEqual(UsageProvider.cursor.secondaryLabel, "Other Models")
        XCTAssertFalse(UsageProvider.cursor.weeklyBlocksPrimary)
        XCTAssertTrue(UsageProvider.claude.weeklyBlocksPrimary)
        XCTAssertTrue(UsageProvider.codex.weeklyBlocksPrimary)
    }

    func testCursorSpentSecondaryPoolDoesNotBlockPrimary() {
        var data = UsageData()
        data.percentage = 40
        data.weeklyPercentage = 100
        data.weeklyBlocksPrimary = false
        XCTAssertEqual(data.dailyPercentage, 40)

        data.weeklyBlocksPrimary = true
        XCTAssertEqual(data.dailyPercentage, 100)
    }

    func testGrokBotSharesCursorLoginAndHasOnlyAWeeklyRow() {
        XCTAssertEqual(UsageProvider.grokBot.primaryHost, "cursor.com")
        XCTAssertEqual(UsageProvider.grokBot.primaryLabel, "Weekly")
        XCTAssertNil(UsageProvider.grokBot.secondaryLabel)
        XCTAssertTrue(UsageProvider.grokBot.oauthHostSuffixes.contains("cursor.com"))
        XCTAssertTrue(UsageProvider.grokBot.oauthHostSuffixes.contains("workos.com"))
    }

    @MainActor
    func testGrokBotReadsWeeklyPoolFromSandUsageStatus() async throws {
        let result = try await scrapeCodexFixture("""
        <div>Grok Bot dashboard</div>
        """, beforeScrape: """
        window.fetch = async () => ({
            ok: true, status: 200,
            json: async () => ({
                currentPeriodStart: '2026-09-11T18:43:19.645Z',
                nextResetTimestampUtc: '2026-09-18T18:43:19.645Z',
                usagePercent: 42,
                hasAvailableUsage: true,
                hasNonZeroIncludedLimit: true,
                grokPlanLabel: 'Grok Bot Plan',
                cursorPlanName: 'Pro'
            })
        })
        """, script: GrokBotScrapingScript.script)

        XCTAssertEqual(result["percentage"] as? Int, 42)
        XCTAssertEqual(result["planName"] as? String, "Pro")
        let reset = try XCTUnwrap(result["resetTime"] as? String)
        XCTAssertTrue(reset.hasPrefix("Resets Sep "), reset)
        XCTAssertTrue(reset.contains("2026"), reset)
        XCTAssertEqual(result["success"] as? Bool, true)
    }

    @MainActor
    func testGrokBotAcceptsSnakeCaseSandFields() async throws {
        let result = try await scrapeCodexFixture("""
        <div>Grok Bot dashboard</div>
        """, beforeScrape: """
        window.fetch = async () => ({
            ok: true, status: 200,
            json: async () => ({
                usage_percent: 7,
                next_reset_timestamp_utc: '2026-09-18T18:43:19.645Z',
                has_non_zero_included_limit: true,
                grok_plan_label: 'Grok Bot Plan'
            })
        })
        """, script: GrokBotScrapingScript.script)

        XCTAssertEqual(result["percentage"] as? Int, 7)
        XCTAssertEqual(result["planName"] as? String, "Grok Bot Plan")
        XCTAssertEqual(result["success"] as? Bool, true)
    }

    @MainActor
    func testGrokBotWithoutIncludedPoolReportsNotIncludedNotZero() async throws {
        let result = try await scrapeCodexFixture("""
        <div>Grok Bot dashboard</div>
        """, beforeScrape: """
        window.fetch = async () => ({
            ok: true, status: 200,
            json: async () => ({ usagePercent: 0, hasNonZeroIncludedLimit: false, includedLimitZero: true })
        })
        """, script: GrokBotScrapingScript.script)

        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertEqual(result["error"] as? String, "Your plan does not include Grok Bot usage.")
        XCTAssertTrue(result["percentage"] is NSNull)
    }

    @MainActor
    func testGrokBotUnauthenticatedSandStatusAsksForLogin() async throws {
        let result = try await scrapeCodexFixture("""
        <div>Grok Bot dashboard</div>
        """, beforeScrape: """
        window.fetch = async () => ({ ok: false, status: 401, json: async () => ({}) })
        """, script: GrokBotScrapingScript.script)

        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertEqual(result["error"] as? String, "Click the person icon next to Grok Bot to log in.")
    }

    @MainActor
    func testCursorReadsPoolsFromUsageSummaryAPI() async throws {
        let result = try await scrapeCodexFixture("""
        <div>Cursor dashboard</div>
        """, beforeScrape: """
        window.fetch = async () => ({
            ok: true, status: 200,
            json: async () => ({
                billingCycleStart: '2026-08-18T08:09:13.000Z',
                billingCycleEnd: '2026-09-18T08:09:13.000Z',
                membershipType: 'pro',
                individualUsage: { plan: {
                    enabled: true, used: 1516, limit: 2000, remaining: 484,
                    autoPercentUsed: 3.2977, apiPercentUsed: 0.7111, totalPercentUsed: 3.0626
                }, onDemand: { enabled: false, used: 0, limit: null } }
            })
        })
        """, script: CursorScrapingScript.script)

        // Included is totalPercentUsed, not used/limit cents (1516/2000 = 76%):
        // those cents are stale on two-pool plans and match nothing on the site.
        XCTAssertEqual(result["percentage"] as? Int, 3)
        XCTAssertEqual(result["weeklyPercentage"] as? Int, 1)
        XCTAssertEqual(result["sonnetWeeklyPercentage"] as? Int, 3)
        XCTAssertEqual(result["sonnetWeeklyLabel"] as? String, "Cursor Models")
        XCTAssertEqual(result["planName"] as? String, "Pro")
        let reset = try XCTUnwrap(result["resetTime"] as? String)
        XCTAssertTrue(reset.hasPrefix("Resets Sep "), reset)
        XCTAssertTrue(reset.contains("2026"), reset)
        XCTAssertEqual(result["weeklyResetTime"] as? String, reset)
        XCTAssertEqual(result["sonnetWeeklyResetTime"] as? String, reset)
        XCTAssertEqual(result["success"] as? Bool, true)
    }

    @MainActor
    func testCursorIncludedIsTotalPercentNotStaleCentsRatio() async throws {
        // Live trap from two-pool plans: the cents read 2000/2000 (100%) while
        // the pools the site draws are only partly used.
        let result = try await scrapeCodexFixture("""
        <div>Cursor dashboard</div>
        """, beforeScrape: """
        window.fetch = async () => ({
            ok: true, status: 200,
            json: async () => ({
                membershipType: 'pro',
                individualUsage: { plan: {
                    enabled: true, used: 2000, limit: 2000, remaining: 0,
                    autoPercentUsed: 22, apiPercentUsed: 3, totalPercentUsed: 15.4
                } }
            })
        })
        """, script: CursorScrapingScript.script)

        XCTAssertEqual(result["percentage"] as? Int, 15)
        XCTAssertEqual(result["sonnetWeeklyPercentage"] as? Int, 22)
        XCTAssertEqual(result["weeklyPercentage"] as? Int, 3)
    }

    @MainActor
    func testCursorIncludedFallsBackToCentsWithoutTotalPercent() async throws {
        let result = try await scrapeCodexFixture("""
        <div>Cursor dashboard</div>
        """, beforeScrape: """
        window.fetch = async () => ({
            ok: true, status: 200,
            json: async () => ({
                membershipType: 'pro',
                individualUsage: { plan: { enabled: true, used: 500, limit: 2000 } }
            })
        })
        """, script: CursorScrapingScript.script)

        XCTAssertEqual(result["percentage"] as? Int, 25)
    }

    @MainActor
    func testCursorReadsOnDemandInDollars() async throws {
        let result = try await scrapeCodexFixture("""
        <div>Cursor dashboard</div>
        """, beforeScrape: """
        window.fetch = async () => ({
            ok: true, status: 200,
            json: async () => ({
                billingCycleEnd: '2026-09-18T08:09:13.000Z',
                membershipType: 'enterprise',
                individualUsage: {
                    plan: { enabled: true, used: 2000, limit: 2000, autoPercentUsed: 10, apiPercentUsed: 90 },
                    onDemand: { enabled: true, used: 1234, limit: null, remaining: null }
                },
                teamUsage: { onDemand: { enabled: true, used: 86000, limit: 1000000, remaining: 914000 } }
            })
        })
        """, script: CursorScrapingScript.script)

        XCTAssertEqual(result["onDemandUsed"] as? Double, 12.34)
        XCTAssertEqual(result["success"] as? Bool, true)
    }

    @MainActor
    func testCursorFallsBackToSpendingPagePoolsWhenAPIHasNoPlan() async throws {
        let result = try await scrapeCodexFixture("""
        <div><span>Cursor Models</span><span>16% used</span></div>
        <div><span>Other Models</span><span>2% used</span></div>
        """, beforeScrape: """
        window.fetch = async () => ({ ok: false, status: 500, json: async () => ({}) })
        """, script: CursorScrapingScript.script)

        XCTAssertEqual(result["sonnetWeeklyPercentage"] as? Int, 16)
        XCTAssertEqual(result["sonnetWeeklyLabel"] as? String, "Cursor Models")
        XCTAssertEqual(result["weeklyPercentage"] as? Int, 2)
        XCTAssertEqual(result["success"] as? Bool, true)
    }

    @MainActor
    func testCursorUnauthenticatedSummaryAsksForLogin() async throws {
        let result = try await scrapeCodexFixture("""
        <div>Cursor dashboard</div>
        """, beforeScrape: """
        window.fetch = async () => ({ ok: false, status: 401, json: async () => ({ error: 'not_authenticated' }) })
        """, script: CursorScrapingScript.script)

        XCTAssertEqual(result["success"] as? Bool, false)
        XCTAssertEqual(result["error"] as? String, "Click the person icon next to Cursor to log in.")
    }

    @MainActor
    func testCodexWeeklyLimitWithResetBeforePercentLeft() async throws {
        let result = try await scrapeCodexFixture("""
        <div><div>Weekly limit</div><div><span>Resets in 7d 0h</span><span>100% left</span></div></div>
        <div>Usage limit resets</div>
        <div>Use a reset to restore your 5-hour limit, weekly limit, or both</div>
        <div>Full reset Expires Oct 22 at 5:12 PM EDT Use reset</div>
        <div>Weekly limits Period % of limit used Sep 29 – Oct 6 44.5%</div>
        """)

        XCTAssertEqual(result["weeklyPercentage"] as? Int, 0)
        XCTAssertEqual(result["weeklyResetTime"] as? String, "Resets in 7d 0h")
        XCTAssertTrue(result["percentage"] is NSNull)
        XCTAssertTrue(result["resetTime"] is NSNull)
        XCTAssertEqual(result["success"] as? Bool, true)
    }

    @MainActor
    func testCodexNewLimitCardsKeepPercentagesAndResetsSeparate() async throws {
        let result = try await scrapeCodexFixture("""
        <div><span>5-hour limit</span><span>Resets in 4h 12m</span><span>91% left</span></div>
        <div><span>Weekly limit</span><span>Resets in 6d 2h</span><span>22% left</span></div>
        """)

        XCTAssertEqual(result["percentage"] as? Int, 9)
        XCTAssertEqual(result["resetTime"] as? String, "Resets in 4h 12m")
        XCTAssertEqual(result["weeklyPercentage"] as? Int, 78)
        XCTAssertEqual(result["weeklyResetTime"] as? String, "Resets in 6d 2h")
    }

    @MainActor
    func testCodexReadsLimitCardsInInactiveOverviewTab() async throws {
        let result = try await scrapeCodexFixture("""
        <div hidden><div><span>Weekly limit</span><span>Resets in 7d 0h</span><span>100% left</span></div></div>
        <div>Usage history</div><div>Weekly limits Period % of limit used Sep 29 – Oct 6 44.5%</div>
        """)

        XCTAssertEqual(result["weeklyPercentage"] as? Int, 0)
        XCTAssertEqual(result["weeklyResetTime"] as? String, "Resets in 7d 0h")
    }

    @MainActor
    func testCodexWaitsForCurrentLimitDespiteHistoricalPercentages() async throws {
        let result = try await scrapeCodexFixture("""
        <div>Weekly limits Period % of limit used Sep 29 – Oct 6 44.5%</div>
        <div id="limit">Loading usage data…</div>
        <script>
          window.showCurrentLimit = () => {
            setTimeout(() => {
              document.getElementById('limit').innerHTML =
                '<div>Weekly usage limit</div><div>22% remaining</div><div>Resets in 6d 2h</div>';
            }, 500);
          };
        </script>
        """, beforeScrape: "window.showCurrentLimit()")

        XCTAssertEqual(result["weeklyPercentage"] as? Int, 78)
        XCTAssertEqual(result["weeklyResetTime"] as? String, "Resets in 6d 2h")
    }

    @MainActor
    func testCodexWeeklyOnlyFixtureDoesNotPopulateDaily() async throws {
        let result = try await scrapeCodexFixture("""
        <div>
          <div>Weekly usage limit</div>
          <div>22% remaining</div>
          <div>Resets Aug 31, 2026 9:01 AM</div>
        </div>
        """)

        XCTAssertTrue(result["percentage"] is NSNull)
        XCTAssertTrue(result["resetTime"] is NSNull)
        XCTAssertEqual(result["weeklyPercentage"] as? Int, 78)
        XCTAssertEqual(result["weeklyResetTime"] as? String, "Resets Aug 31, 2026 9:01 AM")
        XCTAssertEqual(result["success"] as? Bool, true)
    }

    @MainActor
    func testCodexFixtureAssociatesEachResetWithItsLimit() async throws {
        let result = try await scrapeCodexFixture("""
        <div>
          <div>5 hour usage limit</div>
          <div>91% remaining</div>
          <div>Resets 2:30 PM</div>
        </div>
        <div>
          <div>Weekly usage limit</div>
          <div>22% remaining</div>
          <div>Resets August 31, 2026 at 9:01 AM</div>
        </div>
        """)

        XCTAssertEqual(result["percentage"] as? Int, 9)
        XCTAssertEqual(result["resetTime"] as? String, "Resets 2:30 PM")
        XCTAssertEqual(result["weeklyPercentage"] as? Int, 78)
        XCTAssertEqual(result["weeklyResetTime"] as? String, "Resets August 31, 2026 at 9:01 AM")
    }

    @MainActor
    func testCodexHundredPercentRemainingMeansZeroPercentUsed() async throws {
        let result = try await scrapeCodexFixture("""
        <div>
          <div>Weekly usage limit</div>
          <div>100% remaining</div>
          <div>Resets Sep 1, 2026 12:00 PM</div>
        </div>
        """)

        XCTAssertEqual(result["weeklyPercentage"] as? Int, 0)
        XCTAssertTrue(result["percentage"] is NSNull)
    }

    @MainActor
    func testCodexResetIgnoresExplanatoryResetCopy() async throws {
        let result = try await scrapeCodexFixture("""
        <div>
          <div>Weekly usage limit</div>
          <div>22% remaining</div>
          <div>Resets</div>
          <div>Use a reset to restore your weekly limit.</div>
          <div>Resets August 31, 2026 at 9:01 AM</div>
        </div>
        """)

        XCTAssertEqual(result["weeklyPercentage"] as? Int, 78)
        XCTAssertEqual(result["weeklyResetTime"] as? String, "Resets August 31, 2026 at 9:01 AM")
    }

    @MainActor
    func testCodexCountsEachUseResetButtonAsAnAvailableReset() async throws {
        let result = try await scrapeCodexFixture("""
        <div><span>Weekly limit</span><span>Resets in 6d 2h</span><span>22% left</span></div>
        <div>Usage limit resets</div>
        <div>Use a reset to restore your 5-hour limit, weekly limit, or both</div>
        <div>Full reset Expires Oct 22 at 5:12 PM EDT <button>Use reset</button></div>
        <div>Weekly reset Expires Oct 29 at 5:12 PM EDT <button>Use reset</button></div>
        """)

        XCTAssertEqual(result["availableResets"] as? Int, 2)
        XCTAssertEqual(UsageReset.list(from: result["resets"]), [
            UsageReset(title: "Full reset", expires: "Oct 22 at 5:12 PM EDT"),
            UsageReset(title: "Weekly reset", expires: "Oct 29 at 5:12 PM EDT")
        ])
    }

    @MainActor
    func testCodexReadsResetDetailsFromNestedRowSpans() async throws {
        let result = try await scrapeCodexFixture("""
        <div><span>Weekly limit</span><span>Resets in 6d 2h</span><span>22% left</span></div>
        <div>Usage limit resets</div>
        <ul>
          <li><div><span>Full reset</span><span>Expires Nov 10, 3:00 PM EST</span></div><button><span>Use reset</span></button></li>
          <li><div><span>Usage reset</span><span>Expires Nov 17, 3:00 PM EST</span></div><button><span>Use reset</span></button></li>
        </ul>
        """)

        XCTAssertEqual(UsageReset.list(from: result["resets"]), [
            UsageReset(title: "Full reset", expires: "Nov 10, 3:00 PM EST"),
            UsageReset(title: "Usage reset", expires: "Nov 17, 3:00 PM EST")
        ])
    }

    @MainActor
    func testCodexWaitsForResetButtonsThatRenderAfterTheLimitCards() async throws {
        let result = try await scrapeCodexFixture("""
        <div><span>Weekly limit</span><span>Resets in 6d 2h</span><span>22% left</span></div>
        <div id="resets">Usage limit resets</div>
        """, beforeScrape: """
        setTimeout(() => document.getElementById('resets').insertAdjacentHTML('beforeend',
            '<button>Use reset</button><button>Use reset</button>'), 1000)
        """)

        XCTAssertEqual(result["availableResets"] as? Int, 2)
    }

    @MainActor
    func testCodexResetsSectionWithoutButtonsMeansZeroAvailable() async throws {
        let result = try await scrapeCodexFixture("""
        <div><span>Weekly limit</span><span>Resets in 6d 2h</span><span>22% left</span></div>
        <div>Usage limit resets</div>
        <div>Use a reset to restore your 5-hour limit, weekly limit, or both</div>
        <script>const strings = { useReset: "Use reset" };</script>
        """)

        XCTAssertEqual(result["availableResets"] as? Int, 0)
    }

    @MainActor
    func testCodexWithoutResetsSectionLeavesAvailableResetsUnset() async throws {
        let result = try await scrapeCodexFixture("""
        <div><span>Weekly limit</span><span>Resets in 6d 2h</span><span>22% left</span></div>
        """)

        XCTAssertTrue(result["availableResets"] is NSNull)
    }

    @MainActor
    func testClaudeResetsCountsResetForFreeButtons() async throws {
        let result = try await scrapeCodexFixture("""
        <div>Weekly limits</div><div role="progressbar"></div>
        <button>Reset for free</button>
        <button>Reset password</button>
        """, script: ClaudeResetsScript.script)

        XCTAssertEqual(result["availableResets"] as? Int, 1)
        XCTAssertEqual(UsageReset.list(from: result["resets"]), [UsageReset(title: nil, expires: nil)])
    }

    @MainActor
    func testClaudeResetsReadsEachExpiration() async throws {
        let result = try await scrapeCodexFixture("""
        <div>Weekly limits</div>
        <div><span>Weekly reset</span><span>Expires Nov 12</span><button>Reset for free</button></div>
        <div><span>Weekly reset</span><span>Expires Nov 19</span><button>Reset for free</button></div>
        """, script: ClaudeResetsScript.script)

        XCTAssertEqual(UsageReset.list(from: result["resets"]), [
            UsageReset(title: "Weekly reset", expires: "Nov 12"),
            UsageReset(title: "Weekly reset", expires: "Nov 19")
        ])
    }

    @MainActor
    func testClaudeResetsWaitsForButtonsThatRenderLate() async throws {
        let result = try await scrapeCodexFixture("""
        <div id="usage">Weekly limits</div>
        """, beforeScrape: """
        setTimeout(() => document.getElementById('usage').insertAdjacentHTML('beforeend',
            '<button>Reset for free</button>'), 1000)
        """, script: ClaudeResetsScript.script)

        XCTAssertEqual(result["availableResets"] as? Int, 1)
    }

    @MainActor
    func testCodexReadsMonthlyCreditsFromUsageAPI() async throws {
        let result = try await scrapeCodexFixture("""
        <div><span>Weekly limit</span><span>Resets in 6d 2h</span><span>22% left</span></div>
        """, beforeScrape: """
        window.fetch = async (url) => ({
            ok: true,
            json: async () => url === '/api/auth/session'
                ? { accessToken: 'token', account: { id: 'account' } }
                : { spend_control: { individual_limit: { unit: 'credit', limit: '5000', used: '533.5' } } }
        })
        """)

        XCTAssertEqual(result["creditsUsed"] as? Double, 533.5)
        XCTAssertEqual(result["creditsLimit"] as? Double, 5000)
    }

    @MainActor
    func testCodexLeavesCreditsNullWhenUsageAPIFails() async throws {
        let result = try await scrapeCodexFixture("""
        <div><span>Weekly limit</span><span>Resets in 6d 2h</span><span>22% left</span></div>
        """, beforeScrape: """
        window.fetch = async () => ({ ok: false, status: 401, json: async () => ({ accessToken: 'token' }) })
        """)

        XCTAssertTrue(result["creditsUsed"] is NSNull)
        XCTAssertEqual(result["weeklyPercentage"] as? Int, 78)
    }

    @MainActor
    func testCodexLeavesCreditsNullForZeroOrMissingLimit() async throws {
        for limit in ["{ unit: 'credit', limit: '0', used: '0' }", "{ unit: 'credit', limit: null, used: null }"] {
            let result = try await scrapeCodexFixture("""
            <div><span>Weekly limit</span><span>Resets in 6d 2h</span><span>22% left</span></div>
            """, beforeScrape: """
            window.fetch = async (url) => ({
                ok: true,
                json: async () => url === '/api/auth/session'
                    ? { accessToken: 'token' }
                    : { spend_control: { individual_limit: \(limit) } }
            })
            """)

            XCTAssertTrue(result["creditsUsed"] is NSNull, limit)
            XCTAssertTrue(result["creditsLimit"] is NSNull, limit)
        }
    }

    @MainActor
    private func scrapeCodexFixture(_ body: String, beforeScrape: String = "", script: String = CodexScrapingScript.script) async throws -> [String: Any] {
        let webView = WKWebView()
        let navigationWaiter = NavigationWaiter()

        await withCheckedContinuation { continuation in
            navigationWaiter.didFinish = { continuation.resume() }
            webView.navigationDelegate = navigationWaiter
            webView.loadHTMLString("<html><body>\(body)</body></html>", baseURL: nil)
        }

        let value = try await webView.callAsyncJavaScript(
            beforeScrape + ";\n" + script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        return try XCTUnwrap(value as? [String: Any])
    }
}

private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    var didFinish: (() -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish?()
        didFinish = nil
    }
}
