import Foundation

struct BucketTotals: Sendable, Hashable {
    var input: Int = 0
    var cacheWrite: Int = 0
    var cacheRead: Int = 0
    var output: Int = 0
    var costUSD: Double = 0
    var messages: Int = 0

    var totalTokens: Int { input + cacheWrite + cacheRead + output }

    mutating func add(_ r: UsageRecord) {
        input += r.inputTokens
        cacheWrite += r.cacheCreationTokens
        cacheRead += r.cacheReadTokens
        output += r.outputTokens
        costUSD += r.costUSD ?? 0
        messages += 1
    }
}

struct DailyBucket: Sendable, Hashable, Identifiable {
    var date: Date          // start-of-day, user timezone
    var totals: BucketTotals
    var byProvider: [Provider: BucketTotals]
    var byModel: [String: BucketTotals]
    var byProject: [String: BucketTotals]
    var id: Date { date }
}

struct SessionBlock: Sendable, Hashable, Identifiable {
    /// Claude Max session windows are 5h rolling. We approximate by clustering
    /// records into 5h windows anchored on the first message.
    var startedAt: Date
    var endsAt: Date
    var totals: BucketTotals
    var primaryModel: String?
    var id: Date { startedAt }

    var isActive: Bool { Date() < endsAt }
    var remaining: TimeInterval { max(0, endsAt.timeIntervalSinceNow) }
}

enum Aggregator {
    /// Group records by start-of-day in the user's calendar.
    static func dailies(_ records: [UsageRecord], calendar: Calendar = .current) -> [DailyBucket] {
        var buckets: [Date: DailyBucket] = [:]
        for r in records {
            let day = calendar.startOfDay(for: r.timestamp)
            var b = buckets[day] ?? DailyBucket(
                date: day, totals: .init(),
                byProvider: [:], byModel: [:], byProject: [:])
            b.totals.add(r)
            b.byProvider[r.provider, default: .init()].add(r)
            b.byModel[ModelCatalog.displayName(for: r.model), default: .init()].add(r)
            let proj = (r.project?.isEmpty == false ? r.project! : "unattributed")
            b.byProject[proj, default: .init()].add(r)
            buckets[day] = b
        }
        return buckets.values.sorted { $0.date < $1.date }
    }

    /// Cluster Claude Code records into rolling 5-hour session windows
    /// (approximates the Anthropic Max "session" reset behavior).
    static func sessions(_ records: [UsageRecord], window: TimeInterval = 5 * 3600) -> [SessionBlock] {
        let sorted = records
            .filter { $0.provider == .claudeCode || $0.provider == .anthropicAPI }
            .sorted { $0.timestamp < $1.timestamp }
        var blocks: [SessionBlock] = []
        for r in sorted {
            if var last = blocks.last, r.timestamp < last.endsAt {
                last.totals.add(r)
                last.primaryModel = r.model
                blocks[blocks.count - 1] = last
            } else {
                var totals = BucketTotals(); totals.add(r)
                blocks.append(SessionBlock(
                    startedAt: r.timestamp,
                    endsAt: r.timestamp.addingTimeInterval(window),
                    totals: totals,
                    primaryModel: r.model
                ))
            }
        }
        return blocks
    }
}
