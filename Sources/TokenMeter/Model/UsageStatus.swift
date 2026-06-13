import Foundation
import SwiftUI

/// Severity color used across the UI.
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
}

/// What the headline actually means in this moment. Carries both the color
/// severity and the title/body string keys, so the UI never says "예산 거의
/// 다 썼어요" when the real reason is a fast burn rate.
struct UsageStatus: Equatable {
    let level: StatusLevel
    let symbol: String
    let titleKey: LocalizedStringKey
    let bodyKey: LocalizedStringKey
    let titleKeyRaw: String
    let bodyKeyRaw: String

    private init(
        _ level: StatusLevel, _ symbol: String,
        _ title: String, _ body: String
    ) {
        self.level = level
        self.symbol = symbol
        self.titleKey = LocalizedStringKey(title)
        self.bodyKey = LocalizedStringKey(body)
        self.titleKeyRaw = title
        self.bodyKeyRaw = body
    }

    static var idle: UsageStatus {
        .init(.idle, "moon.zzz.fill",
              "status_idle_title", "status_idle_body")
    }
    static var relaxed: UsageStatus {
        .init(.relaxed, "checkmark.circle.fill",
              "status_relaxed_title", "status_relaxed_body")
    }
    static var watchBudget: UsageStatus {
        .init(.watch, "exclamationmark.circle.fill",
              "status_watch_budget_title", "status_watch_budget_body")
    }
    static var watchBurn: UsageStatus {
        .init(.watch, "exclamationmark.circle.fill",
              "status_watch_burn_title", "status_watch_burn_body")
    }
    static var criticalBudget: UsageStatus {
        .init(.critical, "exclamationmark.triangle.fill",
              "status_critical_title", "status_critical_body")
    }
    static var criticalBurn: UsageStatus {
        .init(.critical, "flame.fill",
              "status_burn_critical_title", "status_burn_critical_body")
    }

    /// Decide a status from the active session's budget % and the
    /// burn-rate ratio. Budget always wins when it's high — that's the
    /// concrete, actionable signal. Burn rate raises severity only when
    /// budget is otherwise calm.
    static func decide(percentage: Double, baselineRatio: Double?) -> UsageStatus {
        if percentage >= 0.85 { return .criticalBudget }
        if percentage >= 0.66 { return .watchBudget }
        if let r = baselineRatio {
            if r >= 2.0 { return .criticalBurn }
            if r >= 1.5 { return .watchBurn }
        }
        return .relaxed
    }
}
