import Foundation

/// Adapter contract for any AI tool / API surface that can report token usage.
/// New providers (OpenAI API, Cursor, Windsurf, ...) implement this and the
/// menu bar app aggregates them uniformly.
protocol UsageProvider: Sendable {
    var provider: Provider { get }

    /// One-shot snapshot of all records available right now.
    func snapshot() async throws -> [UsageRecord]

    /// Continuous stream of records as they appear (file watch, polling, etc.).
    /// Each yielded batch represents a delta — callers should merge by record id.
    func live() -> AsyncStream<[UsageRecord]>

    /// Single round-trip used by the "Test connection" UI button.
    /// Should return quickly. Throws if the configuration is invalid.
    /// Default impl reuses snapshot().
    func testConnection() async throws -> TestResult
}

struct TestResult: Sendable {
    let recordsReachable: Int       // count of records returned by the test fetch
    let detail: String              // user-readable summary
}

extension UsageProvider {
    func testConnection() async throws -> TestResult {
        let recs = try await snapshot()
        return TestResult(
            recordsReachable: recs.count,
            detail: recs.isEmpty
                ? "Connected, but no records returned for the test window."
                : "Connected. \(recs.count) records reachable."
        )
    }
}

enum ProviderError: LocalizedError {
    case missingKey
    case http(status: Int, body: String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:           return "No API key configured."
        case .http(let s, let b):   return "HTTP \(s): \(b.prefix(200))"
        case .decode(let m):        return "Decode error: \(m)"
        }
    }
}
