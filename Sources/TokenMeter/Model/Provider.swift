import Foundation
import SwiftUI

enum Provider: String, Sendable, Codable, CaseIterable, Identifiable {
    case claudeCode      = "claude_code"
    case anthropicAPI    = "anthropic_api"
    case openAIAPI       = "openai_api"
    case chatGPTLocal    = "chatgpt_local"   // future: parse local exports
    case cursor          = "cursor"          // future
    case other           = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode:   return "Claude Code"
        case .anthropicAPI: return "Anthropic API"
        case .openAIAPI:    return "OpenAI API"
        case .chatGPTLocal: return "ChatGPT (local)"
        case .cursor:       return "Cursor"
        case .other:        return "Other"
        }
    }

    var color: Color {
        switch self {
        case .claudeCode:   return .orange
        case .anthropicAPI: return .pink
        case .openAIAPI:    return .green
        case .chatGPTLocal: return .mint
        case .cursor:       return .blue
        case .other:        return .gray
        }
    }
}
