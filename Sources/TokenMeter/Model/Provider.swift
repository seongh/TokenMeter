import Foundation
import SwiftUI

/// Data sources TokenMeter can read. We are deliberately Claude-only:
/// other vendors (OpenAI, Google, Cursor, Windsurf, Perplexity) don't
/// expose per-message token counts for their consumer products, so we
/// refuse to fake the numbers.
enum Provider: String, Sendable, Codable, CaseIterable, Identifiable {
    /// Local Claude Code JSONL logs at ~/.claude/projects/*.jsonl.
    case claudeCode      = "claude_code"
    /// Optional: Anthropic Admin API (organization owners only).
    case anthropicAPI    = "anthropic_api"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode:   return "Claude Code"
        case .anthropicAPI: return "Anthropic API"
        }
    }

    var color: Color {
        switch self {
        case .claudeCode:   return .orange
        case .anthropicAPI: return .pink
        }
    }
}
