import Foundation

/// Polls the OpenAI Admin API usage endpoint.
///
/// Endpoint: GET https://api.openai.com/v1/organization/usage/completions
///   Header: Authorization: Bearer sk-admin-...
///   Query: start_time (epoch seconds), end_time, bucket_width=1d, group_by[]=model
///
/// Requires an **admin** API key from the OpenAI org settings. Silent when no key.
final class OpenAIAPIProvider: UsageProvider, @unchecked Sendable {
    let provider: Provider = .openAIAPI
    private let pollInterval: TimeInterval
    private let lock = NSLock()
    private var seenBucketKeys: Set<String> = []

    init(pollInterval: TimeInterval = 600) {
        self.pollInterval = pollInterval
    }

    private var apiKey: String? { Keychain.get("openai_admin_key") }

    func snapshot() async throws -> [UsageRecord] {
        guard let key = apiKey, !key.isEmpty else { return [] }
        return try await fetchUsage(key: key, days: 30)
    }

    func live() -> AsyncStream<[UsageRecord]> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    if let key = self.apiKey, !key.isEmpty {
                        if let recs = try? await self.fetchUsage(key: key, days: 1), !recs.isEmpty {
                            continuation.yield(recs)
                        }
                    }
                    try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func testConnection() async throws -> TestResult {
        guard let key = apiKey, !key.isEmpty else { throw ProviderError.missingKey }
        let recs = try await fetchUsage(key: key, days: 1)
        return TestResult(
            recordsReachable: recs.count,
            detail: "OpenAI Admin API reachable. \(recs.count) usage buckets in last 24h."
        )
    }

    private struct UsageResponse: Decodable {
        struct Bucket: Decodable {
            let start_time: Int
            let end_time: Int
            let results: [Result]
            struct Result: Decodable {
                let input_tokens: Int?
                let input_cached_tokens: Int?
                let output_tokens: Int?
                let num_model_requests: Int?
                let model: String?
            }
        }
        let data: [Bucket]
    }

    private func fetchUsage(key: String, days: Int) async throws -> [UsageRecord] {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        var comps = URLComponents(string: "https://api.openai.com/v1/organization/usage/completions")!
        comps.queryItems = [
            URLQueryItem(name: "start_time", value: String(Int(start.timeIntervalSince1970))),
            URLQueryItem(name: "end_time",   value: String(Int(now.timeIntervalSince1970))),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "group_by[]", value: "model")
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.http(status: -1, body: "no response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderError.http(status: http.statusCode,
                                     body: String(data: data, encoding: .utf8) ?? "")
        }
        let parsed: UsageResponse
        do {
            parsed = try JSONDecoder().decode(UsageResponse.self, from: data)
        } catch {
            throw ProviderError.decode(error.localizedDescription)
        }

        var out: [UsageRecord] = []
        for bucket in parsed.data {
            let startDate = Date(timeIntervalSince1970: TimeInterval(bucket.start_time))
            for r in bucket.results {
                let model = r.model ?? "openai-unknown"
                let key = "openai-\(bucket.start_time)-\(model)"
                let inserted: Bool = {
                    lock.lock(); defer { lock.unlock() }
                    return seenBucketKeys.insert(key).inserted
                }()
                if !inserted { continue }
                let cached = r.input_cached_tokens ?? 0
                let totalIn = r.input_tokens ?? 0
                let freshIn = max(0, totalIn - cached)
                let out_ = r.output_tokens ?? 0
                let cost = ModelCatalog.match(model)?.costUSD(
                    input: freshIn, cacheWrite: 0, cacheRead: cached, output: out_)
                out.append(UsageRecord(
                    id: key,
                    provider: .openAIAPI,
                    model: model,
                    timestamp: startDate,
                    inputTokens: freshIn,
                    cacheCreationTokens: 0,
                    cacheReadTokens: cached,
                    outputTokens: out_,
                    sessionId: nil,
                    project: "OpenAI API",
                    costUSD: cost,
                    webSearchRequests: nil,
                    webFetchRequests: nil))
            }
        }
        return out
    }
}
