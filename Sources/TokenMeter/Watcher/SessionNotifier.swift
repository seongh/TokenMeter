import Foundation
import UserNotifications

/// Sends a banner when the active 5h session crosses budget thresholds.
/// Each threshold fires at most once per session window (deduped by startedAt).
final class SessionNotifier: @unchecked Sendable {
    private let thresholds: [Double] = [0.80, 0.95]   // 80%, 95%
    private let burnRateMultiplier: Double = 1.5      // burn-rate alert sensitivity
    private let lock = NSLock()
    /// (sessionStart, threshold) pairs already fired.
    private var fired: Set<String> = []
    private var burnFired: Set<String> = []          // session-start strings

    init() {}

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func evaluate(session: SessionBlock, budget: Int) {
        guard budget > 0 else { return }
        let pct = Double(session.totals.totalTokens) / Double(budget)
        for t in thresholds where pct >= t {
            let key = "\(Int(session.startedAt.timeIntervalSince1970))-\(t)"
            let inserted: Bool = {
                lock.lock(); defer { lock.unlock() }
                return fired.insert(key).inserted
            }()
            guard inserted else { continue }
            fire(threshold: t, used: session.totals.totalTokens, budget: budget, remaining: session.remaining)
        }
    }

    /// Compare the current session's burn rate against a 7-day per-session
    /// baseline. Notify (once per session) when the current rate is
    /// >= 1.5x faster than baseline and at least 10 minutes have elapsed
    /// in the session (so we don't fire on a single big first message).
    func evaluateBurnRate(session: SessionBlock, baselineTokensPerHour: Double) {
        let elapsedHours = -session.startedAt.timeIntervalSinceNow / 3600
        guard elapsedHours >= (10.0 / 60.0) else { return }
        guard baselineTokensPerHour > 0 else { return }
        let currentRate = Double(session.totals.totalTokens) / elapsedHours
        guard currentRate >= baselineTokensPerHour * burnRateMultiplier else { return }
        let key = String(Int(session.startedAt.timeIntervalSince1970))
        let inserted: Bool = {
            lock.lock(); defer { lock.unlock() }
            return burnFired.insert(key).inserted
        }()
        guard inserted else { return }
        let content = UNMutableNotificationContent()
        content.title = "TokenMeter — burning fast"
        let multiple = currentRate / baselineTokensPerHour
        content.body = String(
            format: "Current session is using tokens %.1f× faster than your 7-day average (%@ /h vs %@ /h baseline).",
            multiple,
            Format.tokens(Int(currentRate)),
            Format.tokens(Int(baselineTokensPerHour)))
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func fire(threshold: Double, used: Int, budget: Int, remaining: TimeInterval) {
        let content = UNMutableNotificationContent()
        let pct = Int(threshold * 100)
        content.title = "TokenMeter — session at \(pct)%"
        content.body = "\(Format.tokens(used)) / \(Format.tokens(budget)) tokens used. Resets in \(Format.clockShort(remaining))."
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
