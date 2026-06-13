import Foundation
import SwiftUI
import Combine

/// Central observable state. Owns providers, merges their records, and exposes
/// derived aggregates (today, this week, sessions, by model/provider) to the UI.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var records: [UsageRecord] = []
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var lastUpdated: Date = .distantPast
    @Published private(set) var detectedInstalls: [InstallProbe.Detection] = []
    @Published private(set) var providerStatuses: [Provider: ProviderStatus] = [:]

    /// Configured plan token budget. Claude Max session limits aren't exposed
    /// by an API; this is a user-tunable target so the UI can show "of budget".
    @AppStorage("sessionTokenBudget") var sessionTokenBudget: Int = 10_000_000
    @AppStorage("weeklyTokenBudget") var weeklyTokenBudget: Int = 50_000_000
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = true

    private var indexById: [String: Int] = [:]
    private var providers: [any UsageProvider] = []
    private var liveTasks: [Task<Void, Never>] = []
    private let store: StateStore
    private let notifier: SessionNotifier
    private weak var claudeCode: ClaudeCodeProvider?
    let folderAccess: ClaudeFolderAccess

    init(providers: [any UsageProvider],
         store: StateStore = .init(),
         notifier: SessionNotifier = .init(),
         folderAccess: ClaudeFolderAccess = .init()) {
        self.providers = providers
        self.store = store
        self.notifier = notifier
        self.folderAccess = folderAccess
        let cc = providers.compactMap { $0 as? ClaudeCodeProvider }.first
        self.claudeCode = cc
        // Seed the provider's root from whichever URL the access layer
        // resolved (direct path outside sandbox, bookmark inside sandbox).
        cc?.updateRoot(folderAccess.rootURL)
        Task { await self.bootstrap() }
    }

    /// Prompt the user to grant the Claude folder via NSOpenPanel, then
    /// rewire the provider and reload snapshots.
    func requestClaudeFolderAccess() async {
        folderAccess.requestAccess()
        claudeCode?.updateRoot(folderAccess.rootURL)
        // Re-bootstrap the Claude Code provider stream now that we have a root.
        await loadSnapshots()
        persist()
    }

    func bootstrap() async {
        // 1. Hydrate from cache (instant).
        let cached = store.load()
        if !cached.records.isEmpty {
            merge(cached.records)
        }
        // Seed Claude Code offsets so its next parse is incremental.
        if let cc = claudeCode, !cached.fileOffsets.isEmpty {
            cc.seed(offsets: cached.fileOffsets, seenIDs: Set(cached.records.map { $0.id }))
        }
        // 2. Run snapshots (may be no-op for cached files).
        await loadSnapshots()
        // 3. Detect other AI tool installs (read-only directory probe only).
        detectedInstalls = InstallProbe.probeAll()
        // 4. Start live streams.
        startLive()
        // 5. Notification permission request (no-op if already granted/denied).
        if notificationsEnabled { await notifier.requestAuthorizationIfNeeded() }
        // 6. Initial persist.
        persist()
    }

    private func loadSnapshots() async {
        for p in providers {
            providerStatuses[p.provider] = .syncing
            do {
                let s = try await p.snapshot()
                let before = records.count
                merge(s)
                let added = records.count - before
                providerStatuses[p.provider] = .ok(lastSync: Date(), addedRecords: added)
            } catch {
                providerStatuses[p.provider] = .error(
                    message: error.localizedDescription, at: Date())
            }
        }
        isLoading = false
    }

    private func startLive() {
        for p in providers {
            let stream = p.live()
            let t = Task { [weak self] in
                for await delta in stream {
                    self?.merge(delta)
                }
            }
            liveTasks.append(t)
        }
    }

    func merge(_ batch: [UsageRecord]) {
        var changed = false
        for r in batch {
            if let i = indexById[r.id] {
                records[i] = r
            } else {
                indexById[r.id] = records.count
                records.append(r)
                changed = true
            }
        }
        if changed {
            records.sort { $0.timestamp < $1.timestamp }
            // rebuild index because indices shifted
            indexById.removeAll(keepingCapacity: true)
            for (i, r) in records.enumerated() { indexById[r.id] = i }
            lastUpdated = Date()
            persist()
            if notificationsEnabled, let s = activeSession {
                notifier.evaluate(session: s, budget: sessionTokenBudget)
            }
        }
    }

    private func persist() {
        let offsets = claudeCode?.currentOffsets() ?? [:]
        let snapshot = PersistedState(
            records: records,
            fileOffsets: offsets,
            version: PersistedState.currentVersion
        )
        store.scheduleSave(snapshot)
    }

    // MARK: - Derived

    var todayBucket: DailyBucket? {
        let today = Calendar.current.startOfDay(for: Date())
        return Aggregator.dailies(records).first { $0.date == today }
    }

    var dailies: [DailyBucket] { Aggregator.dailies(records) }

    var lastNDays: [DailyBucket] { lastN(days: 14) }

    func lastN(days: Int) -> [DailyBucket] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        let map = Dictionary(uniqueKeysWithValues: Aggregator.dailies(records).map { ($0.date, $0) })
        return (0..<days).map { offset in
            let d = cal.date(byAdding: .day, value: offset, to: start)!
            return map[d] ?? DailyBucket(
                date: d, totals: .init(),
                byProvider: [:], byModel: [:], byProject: [:])
        }
    }

    var sessions: [SessionBlock] { Aggregator.sessions(records) }

    var activeSession: SessionBlock? {
        sessions.last.flatMap { $0.isActive ? $0 : nil }
    }

    var weekTotals: BucketTotals {
        var t = BucketTotals()
        for d in lastN(days: 7) { t.add(d.totals) }
        return t
    }

    var allModelsUsed: [String] { Array(Set(records.map { $0.model })).sorted() }

    var currentModel: String? { records.last?.model }

    var totalsByProvider: [(Provider, BucketTotals)] {
        var map: [Provider: BucketTotals] = [:]
        for r in records { map[r.provider, default: .init()].add(r) }
        return map.sorted { $0.value.totalTokens > $1.value.totalTokens }
            .map { ($0.key, $0.value) }
    }

    // MARK: - Project breakdown

    /// Last-N-days totals grouped by Claude Code project (workspace folder).
    /// Records without a project are bucketed under "unattributed".
    func projectTotals(days: Int = 7) -> [(name: String, totals: BucketTotals)] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        var map: [String: BucketTotals] = [:]
        for r in records where r.timestamp >= cutoff {
            let name = (r.project?.isEmpty == false ? r.project! : "unattributed")
            map[name, default: .init()].add(r)
        }
        return map.sorted { $0.value.totalTokens > $1.value.totalTokens }
            .map { (name: $0.key, totals: $0.value) }
    }

    // MARK: - Top expensive messages

    /// Returns the N highest-cost records in the given window. Falls back to
    /// total token count when cost data is missing (e.g. unknown model).
    func topExpensive(days: Int = 7, limit: Int = 10) -> [UsageRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        return records
            .filter { $0.timestamp >= cutoff }
            .sorted { lhs, rhs in
                let lc = lhs.costUSD ?? Double(lhs.totalTokens) / 1_000_000
                let rc = rhs.costUSD ?? Double(rhs.totalTokens) / 1_000_000
                return lc > rc
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - MCP server-side tool use

    /// Sums of web_search / web_fetch calls across the given window.
    func mcpToolTotals(days: Int = 7) -> (webSearch: Int, webFetch: Int) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        var search = 0, fetch = 0
        for r in records where r.timestamp >= cutoff {
            search += r.webSearchRequests ?? 0
            fetch  += r.webFetchRequests ?? 0
        }
        return (search, fetch)
    }

    // MARK: - Export

    func exportData(format: Exporter.Format, days: Int? = nil) -> Data {
        let recs: [UsageRecord]
        if let days {
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
            recs = records.filter { $0.timestamp >= cutoff }
        } else {
            recs = records
        }
        return Exporter.render(recs, as: format)
    }

    // MARK: - Test connection (used by Settings UI)

    func testProvider(_ provider: Provider) async -> TestResult? {
        guard let p = providers.first(where: { $0.provider == provider }) else { return nil }
        providerStatuses[provider] = .syncing
        do {
            let r = try await p.testConnection()
            providerStatuses[provider] = .ok(lastSync: Date(), addedRecords: 0)
            return r
        } catch {
            providerStatuses[provider] = .error(
                message: error.localizedDescription, at: Date())
            return nil
        }
    }
}

extension BucketTotals {
    mutating func add(_ other: BucketTotals) {
        input += other.input
        cacheWrite += other.cacheWrite
        cacheRead += other.cacheRead
        output += other.output
        costUSD += other.costUSD
        messages += other.messages
    }
}
