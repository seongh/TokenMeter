import Foundation

/// Known model metadata: family, context window, and per-million-token pricing.
/// Pricing reflects publicly listed list prices and is used only for cost estimation.
struct ModelInfo: Sendable, Hashable {
    let id: String              // canonical id used in matching (lowercase)
    let displayName: String
    let family: String          // "Claude Opus", "Claude Sonnet", "GPT-4o", ...
    let contextWindow: Int      // tokens
    let inputUSDPerMTok: Double
    let cacheWriteUSDPerMTok: Double
    let cacheReadUSDPerMTok: Double
    let outputUSDPerMTok: Double

    func costUSD(input: Int, cacheWrite: Int, cacheRead: Int, output: Int) -> Double {
        let m = 1_000_000.0
        return Double(input)      * inputUSDPerMTok      / m
             + Double(cacheWrite) * cacheWriteUSDPerMTok / m
             + Double(cacheRead)  * cacheReadUSDPerMTok  / m
             + Double(output)     * outputUSDPerMTok     / m
    }
}

enum ModelCatalog {
    static let all: [ModelInfo] = [
        // Claude 4.x family
        ModelInfo(id: "claude-opus-4",   displayName: "Claude Opus 4",   family: "Claude Opus",
                  contextWindow: 200_000,
                  inputUSDPerMTok: 15, cacheWriteUSDPerMTok: 18.75, cacheReadUSDPerMTok: 1.50, outputUSDPerMTok: 75),
        ModelInfo(id: "claude-opus-4-5", displayName: "Claude Opus 4.5", family: "Claude Opus",
                  contextWindow: 200_000,
                  inputUSDPerMTok: 15, cacheWriteUSDPerMTok: 18.75, cacheReadUSDPerMTok: 1.50, outputUSDPerMTok: 75),
        ModelInfo(id: "claude-opus-4-6", displayName: "Claude Opus 4.6", family: "Claude Opus",
                  contextWindow: 200_000,
                  inputUSDPerMTok: 15, cacheWriteUSDPerMTok: 18.75, cacheReadUSDPerMTok: 1.50, outputUSDPerMTok: 75),
        ModelInfo(id: "claude-opus-4-7", displayName: "Claude Opus 4.7", family: "Claude Opus",
                  contextWindow: 1_000_000,
                  inputUSDPerMTok: 15, cacheWriteUSDPerMTok: 18.75, cacheReadUSDPerMTok: 1.50, outputUSDPerMTok: 75),
        ModelInfo(id: "claude-sonnet-4", displayName: "Claude Sonnet 4", family: "Claude Sonnet",
                  contextWindow: 200_000,
                  inputUSDPerMTok: 3, cacheWriteUSDPerMTok: 3.75, cacheReadUSDPerMTok: 0.30, outputUSDPerMTok: 15),
        ModelInfo(id: "claude-sonnet-4-5", displayName: "Claude Sonnet 4.5", family: "Claude Sonnet",
                  contextWindow: 200_000,
                  inputUSDPerMTok: 3, cacheWriteUSDPerMTok: 3.75, cacheReadUSDPerMTok: 0.30, outputUSDPerMTok: 15),
        ModelInfo(id: "claude-sonnet-4-6", displayName: "Claude Sonnet 4.6", family: "Claude Sonnet",
                  contextWindow: 200_000,
                  inputUSDPerMTok: 3, cacheWriteUSDPerMTok: 3.75, cacheReadUSDPerMTok: 0.30, outputUSDPerMTok: 15),
        ModelInfo(id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5", family: "Claude Haiku",
                  contextWindow: 200_000,
                  inputUSDPerMTok: 1, cacheWriteUSDPerMTok: 1.25, cacheReadUSDPerMTok: 0.10, outputUSDPerMTok: 5)
    ]

    /// Best-effort match: prefer exact id, then longest-prefix.
    static func match(_ rawId: String) -> ModelInfo? {
        let needle = rawId.lowercased()
        if let exact = all.first(where: { $0.id == needle }) { return exact }
        return all
            .filter { needle.hasPrefix($0.id) || needle.contains($0.id) }
            .max(by: { $0.id.count < $1.id.count })
    }

    static func displayName(for rawId: String) -> String {
        match(rawId)?.displayName ?? rawId
    }
}
