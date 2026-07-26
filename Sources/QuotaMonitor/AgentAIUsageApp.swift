import AppKit
import Darwin
import Security
import SwiftUI

struct QuotaLimit: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    var remaining: Double?
}

struct QuotaSnapshot: Equatable {
    var remaining: Double
    var detail: String
    var resetText: String
    var connected: Bool
    var error: String?
    var limits: [QuotaLimit] = []

    static func disconnected(_ detail: String) -> QuotaSnapshot {
        .init(remaining: 0, detail: detail, resetText: T("notConnectedSettings"), connected: false, error: nil)
    }

    static func failed(_ message: String) -> QuotaSnapshot {
        .init(remaining: 0, detail: T("refreshFailed"), resetText: message, connected: false, error: message)
    }
}

struct UsageChange: Codable, Equatable {
    var limitID: String
    var consumed: Double
}

struct UsageEvent: Codable, Identifiable, Equatable {
    var id: UUID
    var taskName: String
    var consumed: Double
    var date: Date
    var changes: [UsageChange]? = nil
}

struct ProviderPoll {
    var snapshot: QuotaSnapshot
    var taskName: String?
}

enum UsageHistory {
    static func load(_ provider: String, defaults: UserDefaults = .standard) -> [UsageEvent] {
        guard let data = defaults.data(forKey: "usageEvents.\(provider)"),
              let events = try? JSONDecoder().decode([UsageEvent].self, from: data) else {
            return []
        }
        let normalized = events.map { event -> UsageEvent in
            var event = event
            if let changes = event.changes,
               changes.contains(where: { $0.limitID != "primary" }) {
                event.changes = changes.filter { $0.limitID != "primary" }
                event.consumed = event.changes?.map(\.consumed).max() ?? event.consumed
            }
            return event
        }
        return Array(normalized.prefix(3))
    }

    static func save(_ events: [UsageEvent], provider: String, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(Array(events.prefix(3))) else { return }
        defaults.set(data, forKey: "usageEvents.\(provider)")
    }
}

private struct QuotaBaseline: Codable {
    var values: [String: Double]
}

@MainActor
final class QuotaStore: ObservableObject {
    typealias ProviderFetcher = () async -> ProviderPoll
    nonisolated static let defaultRefreshInterval: TimeInterval = 30

    @Published var gpt: QuotaSnapshot
    @Published var claude: QuotaSnapshot
    @Published var gptEvents: [UsageEvent]
    @Published var claudeEvents: [UsageEvent]
    @Published var isRefreshing = false
    @Published var lastUpdated: Date?

    private var timer: Timer?
    private let defaults: UserDefaults
    private let gptFetcher: ProviderFetcher
    private let claudeFetcher: ProviderFetcher

    init(
        refreshInterval: TimeInterval = QuotaStore.defaultRefreshInterval,
        autoStart: Bool = true,
        demo: Bool = false,
        defaults: UserDefaults = .standard,
        gptFetcher: @escaping ProviderFetcher = { await QuotaService.fetchCodex() },
        claudeFetcher: @escaping ProviderFetcher = { await QuotaService.fetchClaude() }
    ) {
        self.defaults = defaults
        self.gptFetcher = gptFetcher
        self.claudeFetcher = claudeFetcher
        self.gpt = .disconnected(T("codexConnecting"))
        self.claude = .disconnected(T("claudeNotConnected"))
        self.gptEvents = UsageHistory.load("gpt", defaults: defaults)
        self.claudeEvents = UsageHistory.load("claude", defaults: defaults)

        if demo {
            loadDemoData()
            return
        }
        if autoStart {
            timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            refresh()
        }
    }

    func refresh() {
        Task {
            await refreshNow()
        }
    }

    func refreshNow() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        async let gptResult = gptFetcher()
        async let claudeResult = claudeFetcher()
        let results = await (gptResult, claudeResult)
        apply(results.0, provider: "gpt")
        apply(results.1, provider: "claude")
        lastUpdated = Date()
        isRefreshing = false
    }

    func apply(_ poll: ProviderPoll, provider: String, now: Date = Date()) {
        let snapshot = poll.snapshot
        defer {
            if provider == "gpt" { gpt = snapshot } else { claude = snapshot }
        }
        guard snapshot.connected else { return }

        let current = baselineValues(for: snapshot)
        let key = "lastQuotaLimits.\(provider)"
        let previous = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(QuotaBaseline.self, from: $0) }
        if let data = try? JSONEncoder().encode(QuotaBaseline(values: current)) {
            defaults.set(data, forKey: key)
        }
        guard let previous else { return }

        let changes = current.compactMap { id, remaining -> UsageChange? in
            guard let old = previous.values[id] else { return nil }
            let consumed = old - remaining
            guard consumed >= 0.05 else { return nil }
            return UsageChange(limitID: id, consumed: consumed)
        }.sorted { $0.limitID < $1.limitID }
        guard !changes.isEmpty else { return }

        var events = provider == "gpt" ? gptEvents : claudeEvents
        let title = sanitizedTaskName(poll.taskName, provider: provider)
        if !events.isEmpty,
           events[0].taskName == title,
           now.timeIntervalSince(events[0].date) < 15 * 60 {
            let existingChanges: [UsageChange]
            if let stored = events[0].changes {
                existingChanges = stored
            } else if changes.contains(where: { $0.limitID == "primary" }) {
                existingChanges = [UsageChange(limitID: "primary", consumed: events[0].consumed)]
            } else {
                // Legacy Claude events had one aggregate value. It cannot be
                // assigned safely to a specific modern window, so do not show
                // it as an extra unlabeled pill when new per-window data arrives.
                existingChanges = []
            }
            events[0].changes = merge(existingChanges, with: changes)
            events[0].consumed = events[0].changes?.map(\.consumed).max() ?? events[0].consumed
            events[0].date = now
        } else {
            events.insert(
                UsageEvent(
                    id: UUID(),
                    taskName: title,
                    consumed: changes.map(\.consumed).max() ?? 0,
                    date: now,
                    changes: changes
                ),
                at: 0
            )
        }
        events = Array(events.prefix(3))
        UsageHistory.save(events, provider: provider, defaults: defaults)
        if provider == "gpt" { gptEvents = events } else { claudeEvents = events }
    }

    private func baselineValues(for snapshot: QuotaSnapshot) -> [String: Double] {
        if snapshot.limits.isEmpty { return ["primary": snapshot.remaining] }
        return Dictionary(uniqueKeysWithValues: snapshot.limits.compactMap { limit in
            limit.remaining.map { (limit.id, $0) }
        })
    }

    private func merge(_ existing: [UsageChange], with incoming: [UsageChange]) -> [UsageChange] {
        var values = Dictionary(uniqueKeysWithValues: existing.map { ($0.limitID, $0.consumed) })
        for change in incoming { values[change.limitID, default: 0] += change.consumed }
        return values.map { UsageChange(limitID: $0.key, consumed: $0.value) }
            .sorted { $0.limitID < $1.limitID }
    }

    private func sanitizedTaskName(_ value: String?, provider: String) -> String {
        let fallback = provider == "gpt" ? T("codexConversation") : T("claudeConversation")
        guard let value else { return fallback }
        let compact = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return fallback }
        return String(compact.prefix(52))
    }

    private func loadDemoData() {
        gpt = .init(
            remaining: 78,
            detail: T("weeklyLimit"),
            resetText: String(format: T("resetAt"), "Friday 10:00"),
            connected: true,
            error: nil
        )
        claude = .init(
            remaining: 63,
            detail: T("threeLimits"),
            resetText: T("localSecureSync"),
            connected: true,
            error: nil,
            limits: [
                .init(id: "five_hour", label: T("fiveHours"), remaining: 86),
                .init(id: "seven_day", label: T("thisWeek"), remaining: 63),
                .init(id: "fable", label: T("fable"), remaining: 71)
            ]
        )
        let now = Date()
        gptEvents = [
            .init(id: UUID(), taskName: T("demoGPTTask1"), consumed: 2, date: now.addingTimeInterval(-180), changes: [.init(limitID: "primary", consumed: 2)]),
            .init(id: UUID(), taskName: T("demoGPTTask2"), consumed: 1, date: now.addingTimeInterval(-1_400), changes: [.init(limitID: "primary", consumed: 1)])
        ]
        claudeEvents = [
            .init(id: UUID(), taskName: T("demoClaudeTask1"), consumed: 3, date: now.addingTimeInterval(-320), changes: [
                .init(limitID: "five_hour", consumed: 3),
                .init(limitID: "seven_day", consumed: 1),
                .init(limitID: "fable", consumed: 2)
            ]),
            .init(id: UUID(), taskName: T("demoClaudeTask2"), consumed: 1, date: now.addingTimeInterval(-2_100), changes: [
                .init(limitID: "five_hour", consumed: 1),
                .init(limitID: "seven_day", consumed: 0.4)
            ])
        ]
        lastUpdated = now
    }
}

enum MonitorError: LocalizedError {
    case codexNotFound
    case malformedResponse
    case timedOut
    case server(String)

    var errorDescription: String? {
        switch self {
        case .codexNotFound: return T("codexNotFound")
        case .malformedResponse: return T("malformedResponse")
        case .timedOut: return T("timedOut")
        case .server(let message): return message
        }
    }
}

enum QuotaService {
    static func fetchCodex() async -> ProviderPoll {
        do {
            let payload = try await Task.detached(priority: .utility) {
                try runCodexPollRequest()
            }.value
            let root = payload.rateLimits
            guard
                let result = root["result"] as? [String: Any],
                let limits = result["rateLimits"] as? [String: Any],
                let primary = limits["primary"] as? [String: Any],
                let used = number(primary["usedPercent"])
            else { throw MonitorError.malformedResponse }

            let remaining = max(0, min(100, 100 - used))
            let minutes = number(primary["windowDurationMins"]) ?? 0
            let period = minutes >= 10000 ? T("weeklyLimit") : (minutes >= 1400 ? T("dailyLimit") : T("currentLimit"))
            let reset = number(primary["resetsAt"]).map {
                String(format: T("resetAt"), formatReset(Date(timeIntervalSince1970: $0)))
            } ?? T("codexConnected")
            return ProviderPoll(
                snapshot: .init(
                    remaining: remaining,
                    detail: period,
                    resetText: reset,
                    connected: true,
                    error: nil
                ),
                taskName: payload.taskName
            )
        } catch {
            return ProviderPoll(snapshot: .failed(error.localizedDescription), taskName: nil)
        }
    }

    static func fetchClaude() async -> ProviderPoll {
        let desktopSnapshot = fetchClaudeDesktopUsage()
        if let token = claudeOAuthToken() {
            do {
                return ProviderPoll(
                    snapshot: try await fetchClaudeSubscription(token: token),
                    taskName: latestClaudeTaskName()
                )
            } catch {
                // Claude Desktop remains useful even if an older optional
                // OAuth login expires.
                if let desktopSnapshot {
                    return ProviderPoll(snapshot: desktopSnapshot, taskName: latestClaudeTaskName())
                }
                return ProviderPoll(snapshot: .failed(error.localizedDescription), taskName: nil)
            }
        }
        if let desktopSnapshot {
            return ProviderPoll(snapshot: desktopSnapshot, taskName: latestClaudeTaskName())
        }
        do {
            if let adminKey = Keychain.read("anthropic-admin-key"), !adminKey.isEmpty {
                return ProviderPoll(
                    snapshot: try await fetchClaudeAPIBudget(adminKey: adminKey),
                    taskName: latestClaudeTaskName() ?? T("claudeAPIUsage")
                )
            }
            return ProviderPoll(
                snapshot: .disconnected(T("claudeDesktopOpen")),
                taskName: nil
            )
        } catch {
            return ProviderPoll(snapshot: .failed(error.localizedDescription), taskName: nil)
        }
    }

    static func openClaudeCodeLogin() -> Bool {
        guard let binary = claudeCodeBinary() else { return false }
        let shellPath = "'" + binary.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let command = "\(shellPath) auth login"
        let appleScriptCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
            activate
            do script "\(appleScriptCommand)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }

    private static func claudeCodeBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let root = home.appendingPathComponent(
            "Library/Application Support/Claude/claude-code",
            isDirectory: true
        )
        if let versions = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for version in versions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                let binary = version.appendingPathComponent("claude.app/Contents/MacOS/claude").path
                if FileManager.default.isExecutableFile(atPath: binary) { return binary }
            }
        }
        let candidates = ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:))
    }

    private static func fetchClaudeDesktopUsage() -> QuotaSnapshot? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parseClaudeDesktopUsage(data: data)
    }

    static func parseClaudeDesktopUsage(data: Data, now: Date = Date()) -> QuotaSnapshot? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let samples = root["samples"] as? [[String: Any]],
            let sample = samples.max(by: {
                (number($0["t"]) ?? 0) < (number($1["t"]) ?? 0)
            }),
            let timestamp = number(sample["t"]),
            let usage = sample["u"] as? [String: Any]
        else { return nil }

        // Claude Desktop keeps rolling samples locally. Ignore samples older
        // than the longest quota window so a long-unused installation never
        // looks connected forever.
        let sampledAt = Date(timeIntervalSince1970: timestamp / 1_000)
        guard now.timeIntervalSince(sampledAt) < 8 * 24 * 60 * 60 else { return nil }

        let fiveHour = number(usage["fh"])
        let weekly = number(usage["sd"])
        let fable = fableUtilization(in: root)
        let known = [fiveHour, weekly, fable].compactMap { $0 }
        guard let tightestUsed = known.max() else { return nil }

        let limits = [
            QuotaLimit(id: "five_hour", label: T("fiveHours"), remaining: remaining(fromUsed: fiveHour)),
            QuotaLimit(id: "seven_day", label: T("thisWeek"), remaining: remaining(fromUsed: weekly)),
            QuotaLimit(id: "fable", label: T("fable"), remaining: remaining(fromUsed: fable))
        ]

        return .init(
            remaining: max(0, min(100, 100 - tightestUsed)),
            detail: T("threeLimits"),
            resetText: T("localSecureSync"),
            connected: true,
            error: nil,
            limits: limits
        )
    }

    private static func fetchClaudeSubscription(token: String) async throws -> QuotaSnapshot {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            throw MonitorError.malformedResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("QuotaMonitor/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MonitorError.server(T("claudeExpired"))
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MonitorError.malformedResponse
        }

        let windows: [(String, [String: Any])] = [
            (T("fiveHours"), root["five_hour"] as? [String: Any]),
            (T("thisWeek"), root["seven_day"] as? [String: Any])
        ].compactMap { label, value in value.map { (label, $0) } }

        let parsed = windows.compactMap { label, value -> (String, Double, String?)? in
            guard let utilization = number(value["utilization"]) else { return nil }
            return (label, utilization, value["resets_at"] as? String)
        }
        guard let tightest = parsed.max(by: { $0.1 < $1.1 }) else {
            throw MonitorError.malformedResponse
        }
        let resetDate = tightest.2.flatMap(isoDate)
        let fableUsed = fableUtilization(in: root)
        return .init(
            remaining: max(0, min(100, 100 - tightest.1)),
            detail: T("threeLimits"),
            resetText: resetDate.map { String(format: T("resetAt"), formatReset($0)) } ?? T("claudeConnected"),
            connected: true,
            error: nil,
            limits: [
                QuotaLimit(
                    id: "five_hour",
                    label: T("fiveHours"),
                    remaining: remaining(fromUsed: number((root["five_hour"] as? [String: Any])?["utilization"]))
                ),
                QuotaLimit(
                    id: "seven_day",
                    label: T("thisWeek"),
                    remaining: remaining(fromUsed: number((root["seven_day"] as? [String: Any])?["utilization"]))
                ),
                QuotaLimit(id: "fable", label: T("fable"), remaining: remaining(fromUsed: fableUsed))
            ]
        )
    }

    private static func remaining(fromUsed used: Double?) -> Double? {
        used.map { max(0, min(100, 100 - $0)) }
    }

    private static func fableUtilization(in root: [String: Any]) -> Double? {
        let possibleArrays = [root["limits"], root["usage_limits"]]
        for value in possibleArrays {
            guard let limits = value as? [[String: Any]] else { continue }
            for limit in limits {
                let scope = limit["scope"] as? [String: Any]
                let model = scope?["model"] as? [String: Any]
                let directModel = limit["model"] as? [String: Any]
                let name = (model?["display_name"] as? String)
                    ?? (directModel?["display_name"] as? String)
                    ?? (limit["display_name"] as? String)
                    ?? ""
                guard name.localizedCaseInsensitiveContains("fable") else { continue }
                return number(limit["percent"])
                    ?? number(limit["utilization"])
            }
        }
        return nil
    }

    private static func fetchClaudeAPIBudget(adminKey: String) async throws -> QuotaSnapshot {
        let budget = UserDefaults.standard.double(forKey: "anthropicMonthlyBudget")
        guard budget > 0 else {
            return .disconnected(T("apiBudgetRequired"))
        }
        let interval = monthInterval()
        var components = URLComponents(string: "https://api.anthropic.com/v1/organizations/cost_report")!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: isoString(interval.start)),
            URLQueryItem(name: "ending_at", value: isoString(interval.end)),
            URLQueryItem(name: "limit", value: "31")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue(adminKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("QuotaMonitor/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MonitorError.server(T("apiKeyInvalid"))
        }
        let object = try JSONSerialization.jsonObject(with: data)
        let spentCents = sumClaudeCostCents(object)
        let spent = spentCents / 100
        let remaining = max(0, min(100, (budget - spent) / budget * 100))
        return .init(
            remaining: remaining,
            detail: String(format: T("apiBudgetUsed"), String(format: "%.2f", spent)),
            resetText: String(format: T("apiBudgetReset"), String(format: "%.0f", budget)),
            connected: true,
            error: nil
        )
    }

    private struct CodexPollPayload {
        var rateLimits: [String: Any]
        var taskName: String?
    }

    private static func runCodexPollRequest() throws -> CodexPollPayload {
        let paths = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        guard let binary = paths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw MonitorError.codexNotFound
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var buffer = Data()
        var rateResponse: [String: Any]?
        var threadResponse: [String: Any]?
        var didSignal = false

        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            lock.lock()
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                   let id = number(object["id"]) {
                    if id == 2 { rateResponse = object }
                    if id == 3 { threadResponse = object }
                }
            }
            let ready = rateResponse != nil && threadResponse != nil && !didSignal
            if ready { didSignal = true }
            lock.unlock()
            if ready { semaphore.signal() }
        }

        try process.run()
        let messages = [
            #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"agent-ai-usage","title":"Agent AI Usage","version":"1.1.0"}}}"#,
            #"{"method":"initialized","params":{}}"#,
            #"{"method":"account/rateLimits/read","id":2,"params":{}}"#,
            #"{"method":"thread/list","id":3,"params":{"limit":3,"sortKey":"updated_at","sortDirection":"desc","useStateDbOnly":true}}"#
        ].joined(separator: "\n") + "\n"
        input.fileHandleForWriting.write(Data(messages.utf8))

        let result = semaphore.wait(timeout: .now() + 15)
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        guard result == .success else { throw MonitorError.timedOut }
        lock.lock()
        defer { lock.unlock() }
        guard let rateResponse else { throw MonitorError.malformedResponse }
        return CodexPollPayload(
            rateLimits: rateResponse,
            taskName: codexTaskName(from: threadResponse)
        )
    }

    private static func codexTaskName(from response: [String: Any]?) -> String? {
        guard let result = response?["result"] as? [String: Any],
              let threads = result["data"] as? [[String: Any]],
              let thread = threads.first else { return nil }
        if let name = thread["name"] as? String, !name.isEmpty { return name }
        if let preview = thread["preview"] as? String, !preview.isEmpty {
            return preview.components(separatedBy: .newlines).first
        }
        return nil
    }

    private static func claudeOAuthToken() -> String? {
        if let saved = Keychain.read("claude-oauth-token"), !saved.isEmpty { return saved }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        guard
            let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String,
            !token.isEmpty
        else { return nil }
        return token
    }

    private static func latestClaudeTaskName() -> String? {
        if let title = latestClaudeDesktopTaskName() { return title }

        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newest: (url: URL, date: Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let date = values.contentModificationDate else { continue }
            if newest == nil || date > newest!.date { newest = (url, date) }
        }
        guard let url = newest?.url,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 256 * 1024)) ?? Data()
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "user",
                  let message = object["message"] as? [String: Any],
                  let content = message["content"] else { continue }
            let title: String?
            if let string = content as? String {
                title = string
            } else if let blocks = content as? [[String: Any]] {
                title = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String
            } else {
                title = nil
            }
            guard let title else { continue }
            let compact = title.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !compact.isEmpty, !compact.hasPrefix("<") { return compact }
        }
        return nil
    }

    private static func latestClaudeDesktopTaskName() -> String? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Claude/claude-code-sessions",
                isDirectory: true
            )
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newest: (title: String, activity: Double)?
        for case let url as URL in enumerator where url.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: url),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let title = object["title"] as? String,
                !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            let activity = number(object["lastActivityAt"])
                ?? number(object["lastFocusedAt"])
                ?? number(object["createdAt"])
                ?? 0
            if newest == nil || activity > newest!.activity {
                newest = (title, activity)
            }
        }
        return newest?.title
    }

    private static func sumClaudeCostCents(_ value: Any) -> Double {
        if let dict = value as? [String: Any] {
            if let amount = dict["amount"] {
                return number(amount) ?? 0
            }
            return dict.values.reduce(0) { $0 + sumClaudeCostCents($1) }
        }
        if let array = value as? [Any] {
            return array.reduce(0) { $0 + sumClaudeCostCents($1) }
        }
        return 0
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func monthInterval() -> DateInterval {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        return DateInterval(start: start, end: end)
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func isoDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private static func formatReset(_ date: Date) -> String {
        let formatter = DateFormatter()
        let language = L10n.currentLanguage
        formatter.locale = Locale(identifier: language.localeIdentifier)
        if Calendar.current.isDateInToday(date) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        }
        return formatter.string(from: date)
    }
}

enum Keychain {
    private static let service = "com.konako.quotamonitor"

    static func save(_ value: String, key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        WidgetWindowManager.shared.window = window
        if DemoMode.enabled {
            window.title = "Agent AI Usage — Demo"
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = true
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.level = .normal
            window.collectionBehavior = []
            return
        }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.borderless, .fullSizeContentView]
        window.isOpaque = false
        window.backgroundColor = .clear
        // A system window shadow follows the rectangular window bounds and shows
        // up as an ugly black box around a transparent desktop widget.
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        // Finder's desktop-icon level keeps the widget above the wallpaper, but
        // below every normal application window—matching a desktop widget.
        // One level above Finder icons also keeps mouse dragging responsive.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.isExcludedFromWindowsMenu = true
        window.setFrameAutosaveName("QuotaMonitorWidgetPosition")

        if !UserDefaults.standard.bool(forKey: "didPositionWidgetV5") {
            UserDefaults.standard.set(true, forKey: "didPositionWidgetV5")
            // SwiftUI applies its restored frame shortly after the hosting window
            // appears, so move only after content sizing has settled.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                WidgetWindowManager.shared.moveToPointerScreen()
            }
        }
    }
}

@MainActor
private final class WidgetWindowManager {
    static let shared = WidgetWindowManager()
    weak var window: NSWindow?

    func moveToPointerScreen() {
        guard let window else { return }
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        window.setFrameOrigin(NSPoint(
            x: visible.maxX - window.frame.width - 28,
            y: visible.maxY - window.frame.height - 28
        ))
        window.orderFrontRegardless()
    }
}

private struct DesktopGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 26
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.state = .active
    }
}

private final class NativeDragView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NativeDragView {
        let view = NativeDragView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ view: NativeDragView, context: Context) { }
}

private struct LiquidGlassSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(
                .regular.tint(Color.primary.opacity(0.025)).interactive(),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
        } else {
            content
                .background(DesktopGlass())
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

private struct ProviderBadge: View {
    let resourceName: String

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: resourceName, withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "sparkles")
                    .resizable()
                    .scaledToFit()
                    .padding(7)
                    .background(Color.primary.opacity(0.08))
            }
        }
        .scaledToFill()
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        }
    }
}

private struct AnimatedQuotaTrack: View {
    let value: Double
    let color: Color
    let connected: Bool
    let refreshing: Bool
    @State private var displayedValue = 0.0
    @State private var pulse = false

    var body: some View {
        GeometryReader { proxy in
            let width = max(connected ? 4 : 0, proxy.size.width * displayedValue / 100)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.075))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.76), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width)
                    .overlay(alignment: .trailing) {
                        Circle()
                            .fill(Color.white.opacity(refreshing && connected ? 0.9 : 0))
                            .frame(width: 5, height: 5)
                            .blur(radius: 1.5)
                            .scaleEffect(pulse ? 1.8 : 0.6)
                    }
            }
        }
        .frame(height: 6)
        .onAppear {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.82)) {
                displayedValue = value
            }
        }
        .onChange(of: value) { _, newValue in
            withAnimation(.spring(response: 0.65, dampingFraction: 0.80)) {
                displayedValue = newValue
            }
        }
        .onChange(of: refreshing) { _, active in
            guard active else { pulse = false; return }
            pulse = false
            withAnimation(.easeInOut(duration: 0.55).repeatCount(3, autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct QuotaRow: View {
    let name: String
    let logoResource: String
    let snapshot: QuotaSnapshot
    let refreshing: Bool
    let events: [UsageEvent]
    let language: AppLanguage
    @Binding var expanded: Bool

    private var healthColor: Color {
        guard snapshot.connected else { return .secondary.opacity(0.42) }
        return healthColor(for: snapshot.remaining)
    }

    private func healthColor(for remaining: Double?) -> Color {
        guard let remaining else { return .secondary.opacity(0.34) }
        return Color(
            hue: max(0, min(1, remaining / 100)) * 0.34,
            saturation: 0.78,
            brightness: 0.88
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if snapshot.limits.isEmpty {
                standardSummary
            } else {
                multiLimitSummary
            }

            Button {
                guard !events.isEmpty else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text(events.isEmpty ? T("historyEmpty", language: language) : T("recentTasks", language: language))
                    if !events.isEmpty {
                        Text("\(events.count)")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.07), in: Capsule())
                    }
                    Spacer()
                    if !events.isEmpty {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.88))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 41)
            .frame(height: 20)

            if expanded && !events.isEmpty {
                VStack(spacing: 4) {
                    ForEach(events.prefix(3)) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(healthColor.opacity(0.72))
                                    .frame(width: 4, height: 4)
                                Text(event.taskName)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 6)
                                Text(relativeTime(event.date))
                                    .font(.system(size: 7.5, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                            HStack(spacing: 3) {
                                ForEach(Array(displayChanges(event).prefix(3)), id: \.limitID) { change in
                                    Text(changeText(change))
                                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(Color.orange)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 3)
                                        .background(Color.orange.opacity(0.10), in: Capsule())
                                }
                            }
                            .padding(.leading, 11)
                        }
                        .font(.system(size: 9.5, weight: .medium))
                        .frame(height: 38)
                    }
                }
                .padding(.leading, 41)
                .padding(.top, 3)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: events)
    }

    private var standardSummary: some View {
        HStack(spacing: 11) {
            ProviderBadge(resourceName: logoResource)

            VStack(alignment: .leading, spacing: 7) {
                providerTitle
                AnimatedQuotaTrack(
                    value: snapshot.remaining,
                    color: healthColor,
                    connected: snapshot.connected,
                    refreshing: refreshing
                )
                Text(snapshot.resetText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.85))
                    .lineLimit(1)
            }

            Group {
                if snapshot.connected {
                    (Text("\(Int(snapshot.remaining.rounded()))")
                    + Text("%").font(.system(size: 10, weight: .semibold, design: .rounded)))
                        .contentTransition(.numericText(value: snapshot.remaining))
                } else {
                    Text("—")
                }
            }
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(healthColor)
            .frame(width: 48, alignment: .trailing)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: snapshot.remaining)
        }
        .frame(height: 64)
    }

    private var multiLimitSummary: some View {
        HStack(alignment: .top, spacing: 11) {
            ProviderBadge(resourceName: logoResource)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                providerTitle

                ForEach(snapshot.limits) { limit in
                    HStack(spacing: 7) {
                        Text(limit.label)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(limit.remaining == nil ? .secondary : .primary)
                            .frame(width: 43, alignment: .leading)

                        AnimatedQuotaTrack(
                            value: limit.remaining ?? 0,
                            color: healthColor(for: limit.remaining),
                            connected: limit.remaining != nil,
                            refreshing: refreshing
                        )

                        Text(limit.remaining.map { "\(Int($0.rounded()))%" } ?? "—")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(healthColor(for: limit.remaining))
                            .contentTransition(.numericText(value: limit.remaining ?? 0))
                            .frame(width: 33, alignment: .trailing)
                    }
                    .frame(height: 15)
                }

                Text(snapshot.resetText)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.82))
                    .lineLimit(1)
            }
        }
        .padding(.top, 6)
        .frame(height: 102, alignment: .top)
    }

    private var providerTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(snapshot.detail)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func formattedConsumption(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.05 { return String(Int(value.rounded())) }
        return String(format: "%.1f", value)
    }

    private func relativeTime(_ date: Date) -> String {
        if abs(Date().timeIntervalSince(date)) < 60 { return T("justNow", language: language) }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func displayChanges(_ event: UsageEvent) -> [UsageChange] {
        event.changes ?? [UsageChange(limitID: "primary", consumed: event.consumed)]
    }

    private func changeText(_ change: UsageChange) -> String {
        let prefix: String
        switch change.limitID {
        case "five_hour": prefix = language == .english ? "5h" : T("fiveHours", language: language)
        case "seven_day": prefix = language == .english ? "7d" : T("thisWeek", language: language)
        case "fable": prefix = "Fable"
        default: prefix = ""
        }
        let amount = "−\(formattedConsumption(change.consumed))%"
        return prefix.isEmpty ? amount : "\(prefix) \(amount)"
    }
}

struct WidgetView: View {
    @ObservedObject var store: QuotaStore
    @State private var appeared = false
    @State private var showingHelp = false
    @AppStorage("historyExpanded.gpt") private var gptExpanded = true
    @AppStorage("historyExpanded.claude") private var claudeExpanded = true
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.english.rawValue

    private var language: AppLanguage {
        if DemoMode.enabled { return .english }
        return AppLanguage(rawValue: appLanguageRaw) ?? .english
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(T("appName", language: language))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(updateText)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                Spacer()

                Button { showingHelp.toggle() } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 25, height: 25)
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.055), in: Circle())
                .help(T("helpTooltip", language: language))
                .popover(isPresented: $showingHelp, arrowEdge: .top) {
                    TroubleshootingView(store: store, language: language)
                }

                Button { store.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                        .animation(
                            store.isRefreshing
                                ? .linear(duration: 0.85).repeatForever(autoreverses: false)
                                : .easeOut(duration: 0.2),
                            value: store.isRefreshing
                        )
                        .frame(width: 25, height: 25)
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.055), in: Circle())
                .help(T("refresh", language: language))

                Button { SettingsWindowController.shared.show(store: store) } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 25, height: 25)
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.055), in: Circle())
                .help(T("settings", language: language))
            }
            .padding(.bottom, 9)
            .background(WindowDragHandle())

            QuotaRow(
                name: "GPT · Codex",
                logoResource: "openai",
                snapshot: store.gpt,
                refreshing: store.isRefreshing,
                events: store.gptEvents,
                language: language,
                expanded: $gptExpanded
            )

            Rectangle()
                .fill(Color.primary.opacity(0.075))
                .frame(height: 0.5)
                .padding(.leading, 41)

            QuotaRow(
                name: "Claude",
                logoResource: "claude",
                snapshot: store.claude,
                refreshing: store.isRefreshing,
                events: store.claudeEvents,
                language: language,
                expanded: $claudeExpanded
            )
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(width: 348, height: widgetHeight, alignment: .top)
        .modifier(LiquidGlassSurface())
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
        }
        .background(WindowConfigurator())
        .scaleEffect(appeared ? 1 : 0.97)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.44, dampingFraction: 0.88), value: widgetHeight)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
                appeared = true
            }
        }
        .contextMenu {
            Button(T("refresh", language: language)) { store.refresh() }
            Button(T("settings", language: language)) { SettingsWindowController.shared.show(store: store) }
        }
    }

    private var updateText: String {
        guard let date = store.lastUpdated else { return T("syncing", language: language) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.dateFormat = "HH:mm:ss"
        return String(format: T("updatedFormat", language: language), formatter.string(from: date))
    }

    private var widgetHeight: CGFloat {
        229 + historyHeight(store.gptEvents, expanded: gptExpanded)
            + historyHeight(store.claudeEvents, expanded: claudeExpanded)
            + (store.claude.limits.isEmpty ? 0 : 38)
    }

    private func historyHeight(_ events: [UsageEvent], expanded: Bool) -> CGFloat {
        guard expanded, !events.isEmpty else { return 0 }
        let count = min(events.count, 3)
        return CGFloat(7 + 38 * count + 4 * max(0, count - 1))
    }
}

private struct TroubleshootingView: View {
    @ObservedObject var store: QuotaStore
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.blue)
                Text(T("helpTitle", language: language))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }

            Text(T("helpIntro", language: language))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            statusRow(name: "GPT · Codex", connected: store.gpt.connected)
            Text(T("helpGPT", language: language))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            statusRow(name: "Claude", connected: store.claude.connected)
            Text(T("helpClaude", language: language))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Text(T("helpFable", language: language))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            HStack {
                Button(T("refresh", language: language)) { store.refresh() }
                Button(T("settings", language: language)) {
                    SettingsWindowController.shared.show(store: store)
                }
            }
        }
        .padding(16)
        .frame(width: 330)
    }

    private func statusRow(name: String, connected: Bool) -> some View {
        HStack {
            Circle()
                .fill(connected ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(name)
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            Text(T(connected ? "statusReady" : "statusWaiting", language: language))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct DemoShowcaseView: View {
    @ObservedObject var store: QuotaStore

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.075, blue: 0.12),
                    Color(red: 0.09, green: 0.17, blue: 0.24),
                    Color(red: 0.12, green: 0.08, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.cyan.opacity(0.16))
                .frame(width: 330, height: 330)
                .blur(radius: 85)
                .offset(x: -250, y: -170)
            Circle()
                .fill(Color.purple.opacity(0.18))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: 270, y: 190)

            WidgetView(store: store)
                .shadow(color: .black.opacity(0.34), radius: 34, y: 18)
        }
        .frame(width: 760, height: 620)
        .preferredColorScheme(.dark)
    }
}

struct SettingsView: View {
    @ObservedObject var store: QuotaStore
    @AppStorage("anthropicMonthlyBudget") private var monthlyBudget = 100.0
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.english.rawValue
    @State private var oauthToken = ""
    @State private var adminKey = ""
    @State private var savedMessage = ""

    private var language: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .english
    }

    var body: some View {
        Form {
            Section(T("displaySection", language: language)) {
                Picker(T("language", language: language), selection: $appLanguageRaw) {
                    ForEach(AppLanguage.allCases) { item in
                        Text(item.displayName).tag(item.rawValue)
                    }
                }
                Label(T("desktopWidgetMode", language: language), systemImage: "rectangle.on.rectangle.angled")
                Text(T("desktopWidgetDescription", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(T("codexSection", language: language)) {
                Label(store.gpt.connected ? T("codexDetected", language: language) : T("codexUndetected", language: language),
                      systemImage: store.gpt.connected ? "checkmark.circle.fill" : "exclamationmark.circle")
                Text(T("codexDescription", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(T("claudeSection", language: language)) {
                Label(
                    store.claude.connected ? T("claudeDetected", language: language) : T("claudeUndetected", language: language),
                    systemImage: store.claude.connected ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                Text(T("claudePrivacy", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField(T("oauthPlaceholder", language: language), text: $oauthToken)
                HStack {
                    Button(T("saveSubscription", language: language)) {
                        Keychain.save(oauthToken, key: "claude-oauth-token")
                        savedMessage = T("savedClaude", language: language)
                        store.refresh()
                    }
                    Button(T("connectFable", language: language)) {
                        if QuotaService.openClaudeCodeLogin() {
                            savedMessage = T("finishTerminalLogin", language: language)
                        } else {
                            savedMessage = T("claudeCodeMissing", language: language)
                        }
                    }
                    Button(T("openClaude", language: language)) {
                        let appURL = URL(fileURLWithPath: "/Applications/Claude.app")
                        if !FileManager.default.fileExists(atPath: appURL.path)
                            || !NSWorkspace.shared.open(appURL) {
                            NSWorkspace.shared.open(URL(string: "https://claude.ai/download")!)
                        }
                    }
                }
                Text(T("claudeHelp", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(T("apiFallbackSection", language: language)) {
                SecureField("Anthropic Admin API Key", text: $adminKey)
                HStack {
                    Text(T("monthlyBudget", language: language))
                    TextField("100", value: $monthlyBudget, format: .number)
                        .frame(width: 90)
                }
                Button(T("saveAPI", language: language)) {
                    Keychain.save(adminKey, key: "anthropic-admin-key")
                    savedMessage = T("savedAPI", language: language)
                    store.refresh()
                }
                Text(T("apiFallbackHelp", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !savedMessage.isEmpty {
                Text(savedMessage)
                    .foregroundStyle(.green)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 610)
        .onAppear {
            oauthToken = Keychain.read("claude-oauth-token") ?? ""
            adminKey = Keychain.read("anthropic-admin-key") ?? ""
        }
        .onChange(of: appLanguageRaw) { _, _ in
            savedMessage = ""
            SettingsWindowController.shared.updateTitle()
            store.refresh()
        }
    }
}

@MainActor
private final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var windowController: NSWindowController?

    func show(store: QuotaStore) {
        if let window = windowController?.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let content = SettingsView(store: store)
        let hostingController = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hostingController)
        window.title = T("settingsTitle")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 610))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        windowController = nil
    }

    func updateTitle() {
        windowController?.window?.title = T("settingsTitle")
    }
}

final class QuotaAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard AcceptanceMode.enabled else { return }
        Task { @MainActor in
            let passed = await AcceptanceRunner.run(
                includeLiveProviders: AcceptanceMode.includesLiveProviders
            )
            fflush(stdout)
            Darwin.exit(passed ? 0 : 1)
        }
    }
}

@main
struct QuotaMonitorApp: App {
    @NSApplicationDelegateAdaptor(QuotaAppDelegate.self) private var appDelegate
    @StateObject private var store: QuotaStore
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.english.rawValue

    init() {
        _store = StateObject(wrappedValue: QuotaStore(
            autoStart: !DemoMode.enabled && !AcceptanceMode.enabled,
            demo: DemoMode.enabled
        ))
    }

    private var language: AppLanguage {
        if DemoMode.enabled { return .english }
        return AppLanguage(rawValue: appLanguageRaw) ?? .english
    }

    var body: some Scene {
        WindowGroup {
            if AcceptanceMode.enabled {
                Color.clear.frame(width: 1, height: 1)
            } else if DemoMode.enabled {
                DemoShowcaseView(store: store)
            } else {
                WidgetView(store: store)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra {
            Button(T("showWidget", language: language)) {
                WidgetWindowManager.shared.moveToPointerScreen()
            }
            Button(T("refresh", language: language)) { store.refresh() }
                .keyboardShortcut("r")
            Button(T("settings", language: language)) { SettingsWindowController.shared.show(store: store) }
                .keyboardShortcut(",")
            Divider()
            Button(T("quit", language: language)) { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: "chart.bar.fill")
        }

    }
}
