import Foundation

@MainActor
enum AcceptanceRunner {
    private static var temporarySuites: [String] = []

    private struct Check {
        var name: String
        var passed: Bool
        var detail: String
    }

    static func run(includeLiveProviders: Bool) async -> Bool {
        temporarySuites.removeAll()
        defer {
            for suite in temporarySuites {
                UserDefaults.standard.removePersistentDomain(forName: suite)
            }
            temporarySuites.removeAll()
        }
        var checks: [Check] = []
        func record(_ name: String, _ passed: Bool, _ detail: String = "") {
            checks.append(Check(name: name, passed: passed, detail: detail))
        }

        record("Default refresh interval is 30 seconds", QuotaStore.defaultRefreshInterval == 30)
        record("Default language is English", T("appName", language: .english) == "Agent AI Usage")
        record(
            "English, Simplified Chinese, and Japanese have troubleshooting copy",
            AppLanguage.allCases.allSatisfy { T("helpTitle", language: $0) != "helpTitle" }
        )

        let readyDefaults = isolatedDefaults()
        let readyStore = QuotaStore(
            autoStart: false,
            defaults: readyDefaults,
            gptFetcher: {
                ProviderPoll(snapshot: simpleSnapshot(remaining: 82), taskName: "Launch-ready GPT task")
            },
            claudeFetcher: {
                ProviderPoll(snapshot: claudeSnapshot(fiveHour: 91, weekly: 74, fable: 68), taskName: "Launch-ready Claude task")
            }
        )
        await readyStore.refreshNow()
        record(
            "Providers already available at launch are read immediately",
            readyStore.gpt.connected
                && readyStore.gpt.remaining == 82
                && readyStore.claude.connected
                && readyStore.claude.limits.count == 3
        )

        let delayedSource = DelayedAcceptanceProvider()
        let delayedStore = QuotaStore(
            autoStart: false,
            defaults: isolatedDefaults(),
            gptFetcher: { await delayedSource.fetchGPT() },
            claudeFetcher: { await delayedSource.fetchClaude() }
        )
        await delayedStore.refreshNow()
        let initiallyDisconnected = !delayedStore.gpt.connected && !delayedStore.claude.connected
        await delayedSource.connect()
        await delayedStore.refreshNow()
        record(
            "Providers appearing after launch are detected without restart",
            initiallyDisconnected && delayedStore.gpt.connected && delayedStore.claude.connected
        )

        let historyDefaults = isolatedDefaults()
        let historyStore = QuotaStore(autoStart: false, defaults: historyDefaults)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        historyStore.apply(
            ProviderPoll(snapshot: claudeSnapshot(fiveHour: 90, weekly: 70, fable: 80), taskName: "Build multilingual UI"),
            provider: "claude",
            now: start
        )
        historyStore.apply(
            ProviderPoll(snapshot: claudeSnapshot(fiveHour: 87, weekly: 69, fable: 78), taskName: "Build multilingual UI"),
            provider: "claude",
            now: start.addingTimeInterval(60)
        )
        let firstEvent = historyStore.claudeEvents.first
        record(
            "Claude task captures 5-hour, weekly, and Fable consumption",
            firstEvent?.changes?.count == 3
                && approximately(change("five_hour", in: firstEvent), 3)
                && approximately(change("seven_day", in: firstEvent), 1)
                && approximately(change("fable", in: firstEvent), 2)
        )

        historyStore.apply(
            ProviderPoll(snapshot: claudeSnapshot(fiveHour: 86, weekly: 68.5, fable: 78), taskName: "Build multilingual UI"),
            provider: "claude",
            now: start.addingTimeInterval(120)
        )
        let mergedEvent = historyStore.claudeEvents.first
        record(
            "Repeated changes from the same task merge correctly",
            historyStore.claudeEvents.count == 1
                && approximately(change("five_hour", in: mergedEvent), 4)
                && approximately(change("seven_day", in: mergedEvent), 1.5)
                && approximately(change("fable", in: mergedEvent), 2)
        )

        let migrationDefaults = isolatedDefaults()
        UsageHistory.save([
            UsageEvent(
                id: UUID(),
                taskName: "Legacy Claude task",
                consumed: 1,
                date: start,
                changes: nil
            )
        ], provider: "claude", defaults: migrationDefaults)
        let migrationStore = QuotaStore(autoStart: false, defaults: migrationDefaults)
        migrationStore.apply(
            ProviderPoll(snapshot: claudeSnapshot(fiveHour: 90, weekly: 70, fable: 80), taskName: "Baseline"),
            provider: "claude",
            now: start
        )
        migrationStore.apply(
            ProviderPoll(snapshot: claudeSnapshot(fiveHour: 89, weekly: 69.5, fable: 80), taskName: "Legacy Claude task"),
            provider: "claude",
            now: start.addingTimeInterval(60)
        )
        record(
            "Legacy aggregate Claude history does not create an unlabeled pill",
            migrationStore.claudeEvents.first?.changes?.allSatisfy { $0.limitID != "primary" } == true
        )

        let resetStore = QuotaStore(autoStart: false, defaults: isolatedDefaults())
        resetStore.apply(
            ProviderPoll(snapshot: claudeSnapshot(fiveHour: 12, weekly: 30, fable: 20), taskName: "Before reset"),
            provider: "claude",
            now: start
        )
        resetStore.apply(
            ProviderPoll(snapshot: claudeSnapshot(fiveHour: 100, weekly: 100, fable: 100), taskName: "Reset"),
            provider: "claude",
            now: start.addingTimeInterval(60)
        )
        record("Quota resets never create false consumption", resetStore.claudeEvents.isEmpty)

        let cappedDefaults = isolatedDefaults()
        let cappedStore = QuotaStore(autoStart: false, defaults: cappedDefaults)
        cappedStore.apply(ProviderPoll(snapshot: simpleSnapshot(remaining: 100), taskName: "Baseline"), provider: "gpt", now: start)
        for index in 1...4 {
            cappedStore.apply(
                ProviderPoll(snapshot: simpleSnapshot(remaining: 100 - Double(index)), taskName: "Task \(index)"),
                provider: "gpt",
                now: start.addingTimeInterval(Double(index) * 1_000)
            )
        }
        let restoredStore = QuotaStore(autoStart: false, defaults: cappedDefaults)
        record(
            "Only three recent tasks are persisted per provider",
            cappedStore.gptEvents.count == 3 && restoredStore.gptEvents.count == 3
        )

        do {
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let json: [String: Any] = [
                "version": 2,
                "samples": [[
                    "t": now.timeIntervalSince1970 * 1_000,
                    "org": "demo",
                    "u": ["fh": 14, "sd": 37]
                ]],
                "limits": [[
                    "percent": 29,
                    "scope": ["model": ["display_name": "Fable 5"]]
                ]]
            ]
            let data = try JSONSerialization.data(withJSONObject: json)
            let parsed = QuotaService.parseClaudeDesktopUsage(data: data, now: now)
            record(
                "Claude Desktop history and generic Fable limit parse correctly",
                parsed?.limits.first(where: { $0.id == "five_hour" })?.remaining == 86
                    && parsed?.limits.first(where: { $0.id == "seven_day" })?.remaining == 63
                    && parsed?.limits.first(where: { $0.id == "fable" })?.remaining == 71
            )

            let staleJSON: [String: Any] = [
                "version": 2,
                "samples": [[
                    "t": now.addingTimeInterval(-9 * 24 * 60 * 60).timeIntervalSince1970 * 1_000,
                    "u": ["fh": 10, "sd": 20]
                ]]
            ]
            let staleData = try JSONSerialization.data(withJSONObject: staleJSON)
            record(
                "Stale Claude history is rejected",
                QuotaService.parseClaudeDesktopUsage(data: staleData, now: now) == nil
            )
        } catch {
            record("Claude fixture parsing", false, error.localizedDescription)
        }

        if includeLiveProviders {
            async let liveGPT = QuotaService.fetchCodex()
            async let liveClaude = QuotaService.fetchClaude()
            let live = await (liveGPT, liveClaude)
            record(
                "Live GPT / Codex sign-in on this Mac",
                live.0.snapshot.connected,
                live.0.snapshot.resetText
            )
            record(
                "Live Claude sign-in on this Mac",
                live.1.snapshot.connected && !live.1.snapshot.limits.isEmpty,
                live.1.snapshot.resetText
            )
        }

        print("Agent AI Usage acceptance")
        for check in checks {
            let marker = check.passed ? "PASS" : "FAIL"
            let suffix = check.detail.isEmpty ? "" : " — \(check.detail)"
            print("[\(marker)] \(check.name)\(suffix)")
        }
        let failures = checks.filter { !$0.passed }
        print("\n\(checks.count - failures.count)/\(checks.count) checks passed")
        return failures.isEmpty
    }

    private static func isolatedDefaults() -> UserDefaults {
        let suite = "AgentAIUsageAcceptance.\(UUID().uuidString)"
        temporarySuites.append(suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static func simpleSnapshot(remaining: Double) -> QuotaSnapshot {
        .init(remaining: remaining, detail: "Weekly limit", resetText: "Connected", connected: true, error: nil)
    }

    private static func claudeSnapshot(fiveHour: Double, weekly: Double, fable: Double) -> QuotaSnapshot {
        .init(
            remaining: min(fiveHour, min(weekly, fable)),
            detail: "3 limits",
            resetText: "Connected",
            connected: true,
            error: nil,
            limits: [
                .init(id: "five_hour", label: "5 hours", remaining: fiveHour),
                .init(id: "seven_day", label: "Weekly", remaining: weekly),
                .init(id: "fable", label: "Fable", remaining: fable)
            ]
        )
    }

    private static func change(_ id: String, in event: UsageEvent?) -> Double? {
        event?.changes?.first(where: { $0.limitID == id })?.consumed
    }

    private static func approximately(_ value: Double?, _ expected: Double) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 0.001
    }
}

private actor DelayedAcceptanceProvider {
    private var connected = false

    func connect() { connected = true }

    func fetchGPT() -> ProviderPoll {
        guard connected else { return ProviderPoll(snapshot: .disconnected("Waiting"), taskName: nil) }
        return ProviderPoll(
            snapshot: .init(remaining: 76, detail: "Weekly", resetText: "Connected", connected: true, error: nil),
            taskName: "Delayed GPT task"
        )
    }

    func fetchClaude() -> ProviderPoll {
        guard connected else { return ProviderPoll(snapshot: .disconnected("Waiting"), taskName: nil) }
        return ProviderPoll(
            snapshot: .init(
                remaining: 67,
                detail: "3 limits",
                resetText: "Connected",
                connected: true,
                error: nil,
                limits: [
                    .init(id: "five_hour", label: "5 hours", remaining: 88),
                    .init(id: "seven_day", label: "Weekly", remaining: 67),
                    .init(id: "fable", label: "Fable", remaining: 72)
                ]
            ),
            taskName: "Delayed Claude task"
        )
    }
}
