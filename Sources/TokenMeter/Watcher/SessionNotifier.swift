import Foundation
import UserNotifications

/// Sends a banner when the active 5h session crosses budget thresholds.
/// Each threshold fires at most once per session window (deduped by startedAt).
final class SessionNotifier: @unchecked Sendable {
    private let thresholds: [Double] = [0.80, 0.95]   // 80%, 95%
    private let lock = NSLock()
    /// (sessionStart, threshold) pairs already fired.
    private var fired: Set<String> = []

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
