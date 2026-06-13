import Foundation

/// Polls the Anthropic Admin API usage report endpoint.
///
/// Endpoint: GET https://api.anthropic.com/v1/organizations/usage_report/messages
///   Headers: x-api-key, anthropic-version
///   Query: starting_at (ISO8601), ending_at, bucket_width (1d|1h|1m)
///
/// Requires an **admin** API key (sk-ant-admin-...). Standard sk-ant-api-...
/// keys will be rejected by the endpoint. The adapter is silent if no key
/// is configured.
final class AnthropicAPIProvider: UsageProvider, @unchecked Sendable {
    let provider: Provider = .anthropicAPI
    private let pollInterval: TimeInterval
    private let lock = NSLock()
    private var seenBucketKeys: Set<String> = []   // dedupe across polls

    init(pollInterval: TimeInterval = 600) {
        self.pollInterval = pollInterval
    }

    private var apiKey: String? { Keychain.get("anthropic_admin_key") }

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
            detail: "Anthropic Admin API reachable. \(recs.count) usage buckets in last 24h."
        )
    }

    // MARK: - HTTP

    private struct UsageResponse: Decodable {
        struct Bucket: Decodable {
            let starting_at: String
            let ending_at: String
            let results: [Result]
            struct Result: Decodable {
                let uncached_input_tokens: Int?
                let cache_creation_input_tokens: Int?
                let cache_read_input_tokens: Int?
                let output_tokens: Int?
                let model: String?
            }
        }
        let data: [Bucket]
    }

    private func fetchUsage(key: String, days: Int) async throws -> [UsageRecord] {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var comps = URLComponents(string: "https://api.anthropic.com/v1/organizations/usage_report/messages")!
        comps.queryItems = [
            URLQueryItem(name: "starting_at", value: iso.string(from: start)),
            URLQueryItem(name: "ending_at",   value: iso.string(from: now)),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "group_by[]", value: "model")
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
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
            let startDate = iso.date(from: bucket.starting_at) ?? now
            for r in bucket.results {
                let model = r.model ?? "anthropic-unknown"
                let key = "anthropic-\(bucket.starting_at)-\(model)"
                let inserted: Bool = {
                    lock.lock(); defer { lock.unlock() }
                    return seenBucketKeys.insert(key).inserted
                }()
                if !inserted { continue }
                let inp = r.uncached_input_tokens ?? 0
                let cw  = r.cache_creation_input_tokens ?? 0
                let cr  = r.cache_read_input_tokens ?? 0
                let out_ = r.output_tokens ?? 0
                let cost = ModelCatalog.match(model)?.costUSD(
                    input: inp, cacheWrite: cw, cacheRead: cr, output: out_)
                out.append(UsageRecord(
                    id: key,
                    provider: .anthropicAPI,
                    model: model,
                    timestamp: startDate,
                    inputTokens: inp,
                    cacheCreationTokens: cw,
                    cacheReadTokens: cr,
                    outputTokens: out_,
                    sessionId: nil,
                    project: "Anthropic API",
                    costUSD: cost,
                    webSearchRequests: nil,
                    webFetchRequests: nil))
            }
        }
        return out
    }
}
