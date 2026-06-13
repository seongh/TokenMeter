import Testing
import Foundation
@testable import TokenMeter

@Suite("ClaudeCodeProvider")
struct ClaudeCodeProviderTests {

    @Test("parseLine extracts tokens for assistant messages")
    func parsesAssistantLine() throws {
        let json = """
        {"type":"assistant","uuid":"abc-1","timestamp":"2026-06-12T10:00:00.000Z","sessionId":"s1","message":{"model":"claude-opus-4-7","usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_read_input_tokens":1000,"output_tokens":50}}}
        """.data(using: .utf8)!

        let rec = try ClaudeCodeProvider.parseLine(json, project: "demo")
        #expect(rec != nil)
        #expect(rec?.id == "abc-1")
        #expect(rec?.model == "claude-opus-4-7")
        #expect(rec?.inputTokens == 10)
        #expect(rec?.cacheCreationTokens == 100)
        #expect(rec?.cacheReadTokens == 1000)
        #expect(rec?.outputTokens == 50)
        #expect(rec?.sessionId == "s1")
        #expect(rec?.costUSD != nil)
    }

    @Test("parseLine returns nil for non-assistant types")
    func skipsNonAssistant() throws {
        let json = #"{"type":"user","message":{"role":"user","content":"hi"}}"#.data(using: .utf8)!
        let rec = try ClaudeCodeProvider.parseLine(json, project: nil)
        #expect(rec == nil)
    }

    @Test("Aggregator buckets by day")
    func dailyAggregation() {
        let cal = Calendar.current
        let day1 = cal.startOfDay(for: Date())
        let day2 = cal.date(byAdding: .day, value: -1, to: day1)!
        let r1 = UsageRecord(id: "1", provider: .claudeCode, model: "claude-opus-4-7",
                             timestamp: day1, inputTokens: 1, cacheCreationTokens: 0,
                             cacheReadTokens: 0, outputTokens: 10, sessionId: nil,
                             project: nil, costUSD: nil,
                    webSearchRequests: nil, webFetchRequests: nil)
        let r2 = UsageRecord(id: "2", provider: .claudeCode, model: "claude-sonnet-4-6",
                             timestamp: day2, inputTokens: 5, cacheCreationTokens: 0,
                             cacheReadTokens: 0, outputTokens: 20, sessionId: nil,
                             project: nil, costUSD: nil,
                    webSearchRequests: nil, webFetchRequests: nil)
        let dailies = Aggregator.dailies([r1, r2])
        #expect(dailies.count == 2)
        #expect(dailies.first(where: { cal.isDate($0.date, inSameDayAs: day1) })?.totals.totalTokens == 11)
    }

    @Test("ModelCatalog matches Claude Opus 4.7")
    func modelMatch() {
        let m = ModelCatalog.match("claude-opus-4-7")
        #expect(m?.displayName == "Claude Opus 4.7")
        #expect(m?.contextWindow == 1_000_000)
    }

    @Test("Sessions cluster within 5h windows")
    func sessionClustering() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let r1 = make(id: "a", at: t0)
        let r2 = make(id: "b", at: t0.addingTimeInterval(3600))    // +1h
        let r3 = make(id: "c", at: t0.addingTimeInterval(6 * 3600)) // +6h - new session
        let s = Aggregator.sessions([r1, r2, r3])
        #expect(s.count == 2)
        #expect(s.first?.totals.messages == 2)
    }

    private func make(id: String, at: Date) -> UsageRecord {
        UsageRecord(id: id, provider: .claudeCode, model: "claude-opus-4-7",
                    timestamp: at, inputTokens: 1, cacheCreationTokens: 0,
                    cacheReadTokens: 0, outputTokens: 1, sessionId: nil,
                    project: nil, costUSD: nil,
                    webSearchRequests: nil, webFetchRequests: nil)
    }
}

@Suite("StateStore round-trip")
struct StateStoreTests {
    @Test("save + load yields identical state")
    func roundTrip() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenmeter-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = StateStore(url: tmp)
        let rec = UsageRecord(
            id: "x", provider: .claudeCode, model: "claude-opus-4-7",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            inputTokens: 1, cacheCreationTokens: 2, cacheReadTokens: 3,
            outputTokens: 4, sessionId: "s", project: "p", costUSD: 0.01,
            webSearchRequests: 1, webFetchRequests: 2)
        let state = PersistedState(records: [rec], fileOffsets: ["/tmp/a.jsonl": 42], version: 1)
        store.saveNow(state)
        let loaded = store.load()
        #expect(loaded.records.count == 1)
        #expect(loaded.records.first?.id == "x")
        #expect(loaded.fileOffsets["/tmp/a.jsonl"] == 42)
    }
}

@Suite("InstallProbe")
struct InstallProbeTests {
    @Test("probeAll never crashes regardless of system state")
    func safeProbe() {
        let results = InstallProbe.probeAll()
        for d in results {
            #expect(!d.name.isEmpty)
            #expect(!d.path.isEmpty)
        }
    }
}

@Suite("Project aggregation")
struct ProjectAggregationTests {
    @Test("DailyBucket sums byProject correctly")
    func dailyByProject() {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let a = UsageRecord(id: "1", provider: .claudeCode, model: "claude-opus-4-7",
                            timestamp: t, inputTokens: 0, cacheCreationTokens: 0,
                            cacheReadTokens: 100, outputTokens: 10,
                            sessionId: nil, project: "alpha", costUSD: nil,
                            webSearchRequests: nil, webFetchRequests: nil)
        let b = UsageRecord(id: "2", provider: .claudeCode, model: "claude-opus-4-7",
                            timestamp: t, inputTokens: 0, cacheCreationTokens: 0,
                            cacheReadTokens: 200, outputTokens: 20,
                            sessionId: nil, project: "alpha", costUSD: nil,
                            webSearchRequests: nil, webFetchRequests: nil)
        let c = UsageRecord(id: "3", provider: .claudeCode, model: "claude-opus-4-7",
                            timestamp: t, inputTokens: 0, cacheCreationTokens: 0,
                            cacheReadTokens: 50, outputTokens: 5,
                            sessionId: nil, project: "beta", costUSD: nil,
                            webSearchRequests: nil, webFetchRequests: nil)
        let dailies = Aggregator.dailies([a, b, c])
        #expect(dailies.count == 1)
        let bucket = dailies.first!
        #expect(bucket.byProject["alpha"]?.totalTokens == 330)
        #expect(bucket.byProject["beta"]?.totalTokens == 55)
    }

    @Test("records without project bucket as 'unattributed'")
    func unattributedBucket() {
        let r = UsageRecord(id: "x", provider: .anthropicAPI, model: "claude-opus-4-7",
                            timestamp: Date(), inputTokens: 5, cacheCreationTokens: 0,
                            cacheReadTokens: 0, outputTokens: 5,
                            sessionId: nil, project: nil, costUSD: nil,
                            webSearchRequests: nil, webFetchRequests: nil)
        let dailies = Aggregator.dailies([r])
        #expect(dailies.first?.byProject["unattributed"]?.totalTokens == 10)
    }
}

@Suite("ProviderStatus formatting")
struct ProviderStatusTests {
    @Test("ok status formats with relative time")
    func okSummary() {
        let s = ProviderStatus.ok(lastSync: Date(), addedRecords: 3)
        #expect(s.summary.contains("OK"))
        #expect(s.summary.contains("+3"))
        #expect(s.iconName == "checkmark.circle.fill")
    }

    @Test("error status includes message")
    func errorSummary() {
        let s = ProviderStatus.error(message: "401 unauthorized", at: Date())
        #expect(s.summary.contains("401"))
        #expect(s.iconName == "exclamationmark.triangle.fill")
    }
}

