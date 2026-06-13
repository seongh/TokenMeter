import Foundation

/// Per-provider sync state surfaced to the UI.
enum ProviderStatus: Sendable, Equatable {
    case idle
    case syncing
    case ok(lastSync: Date, addedRecords: Int)
    case error(message: String, at: Date)

    var iconName: String {
        switch self {
        case .idle:    return "circle"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .ok:      return "checkmark.circle.fill"
        case .error:   return "exclamationmark.triangle.fill"
        }
    }

    var summary: String {
        switch self {
        case .idle:    return "Not started"
        case .syncing: return "Syncing…"
        case .ok(let date, let n):
            return "OK — \(Format.relative(date))" + (n > 0 ? " (+\(n))" : "")
        case .error(let m, let date):
            return "Error: \(m) (\(Format.relative(date)))"
        }
    }
}
