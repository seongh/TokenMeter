import Foundation
import SwiftUI

/// Unified status level used across the UI so colors and copy stay consistent.
///
/// Mapping:
///   relaxed (< 66%)  — green, "Plenty of room"
///   watch   (66-85%) — orange, "Watch your pace"
///   critical (≥ 85%) — red, "Close to the limit"
///   idle             — gray, "No active session"
enum StatusLevel: Sendable, Equatable {
    case relaxed
    case watch
    case critical
    case idle

    var tint: Color {
        switch self {
        case .relaxed:  return Color(red: 0.20, green: 0.70, blue: 0.35) // muted green
        case .watch:    return Color(red: 0.95, green: 0.60, blue: 0.10) // amber
        case .critical: return Color(red: 0.90, green: 0.25, blue: 0.25) // red
        case .idle:     return Color.gray
        }
    }

    var symbol: String {
        switch self {
        case .relaxed:  return "checkmark.circle.fill"
        case .watch:    return "exclamationmark.circle.fill"
        case .critical: return "exclamationmark.triangle.fill"
        case .idle:     return "moon.zzz.fill"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .relaxed:  return "status_relaxed_title"
        case .watch:    return "status_watch_title"
        case .critical: return "status_critical_title"
        case .idle:     return "status_idle_title"
        }
    }

    var bodyKey: LocalizedStringKey {
        switch self {
        case .relaxed:  return "status_relaxed_body"
        case .watch:    return "status_watch_body"
        case .critical: return "status_critical_body"
        case .idle:     return "status_idle_body"
        }
    }

    /// Classify a progress percentage (0…1) into a status level.
    static func from(percentage: Double, baselineRatio: Double? = nil) -> StatusLevel {
        // Treat both budget % and burn-rate ratio as signals. The worse of
        // the two wins.
        var level: StatusLevel = percentage >= 0.85 ? .critical
                              : percentage >= 0.66 ? .watch
                              : .relaxed
        if let r = baselineRatio {
            if r >= 1.5 && level == .relaxed { level = .watch }
            if r >= 2.0 { level = .critical }
        }
        return level
    }
}
