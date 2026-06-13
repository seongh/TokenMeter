import Foundation

/// One token-accounting event from any provider.
/// Tokens are normalized so the UI can aggregate across providers uniformly.
struct UsageRecord: Sendable, Identifiable, Hashable, Codable {
    let id: String                  // stable id (e.g. message uuid)
    let provider: Provider
    let model: String               // raw model id (e.g. "claude-opus-4-7")
    let timestamp: Date
    let inputTokens: Int            // fresh (non-cache) input
    let cacheCreationTokens: Int    // cache write
    let cacheReadTokens: Int        // cache hit
    let outputTokens: Int
    let sessionId: String?          // provider-specific session/conversation id
    let project: String?            // workspace/folder, when known
    let costUSD: Double?            // pre-computed when pricing is known
    /// Anthropic server-side tool calls billed alongside the message.
    let webSearchRequests: Int?
    let webFetchRequests: Int?

    var totalInputTokens: Int { inputTokens + cacheCreationTokens + cacheReadTokens }
    var totalTokens: Int { totalInputTokens + outputTokens }

    /// "Billable equivalent" using the standard Anthropic cache pricing ratios
    /// (cache_creation = 1.25x base input, cache_read = 0.1x base input).
    /// Other providers fall back to raw sum.
    var billableInputEquivalent: Double {
        switch provider {
        case .claudeCode, .anthropicAPI:
            return Double(inputTokens)
                 + Double(cacheCreationTokens) * 1.25
                 + Double(cacheReadTokens) * 0.10
        default:
            return Double(totalInputTokens)
        }
    }
}
