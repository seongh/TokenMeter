import Foundation

enum Format {
    /// 1,234,567 -> "1.23M". Compact for menu bar.
    static func tokens(_ n: Int) -> String {
        let abs = Swift.abs(n)
        switch abs {
        case ..<1_000:        return "\(n)"
        case ..<1_000_000:    return String(format: "%.1fK", Double(n)/1_000)
        case ..<1_000_000_000:return String(format: "%.2fM", Double(n)/1_000_000)
        default:              return String(format: "%.2fB", Double(n)/1_000_000_000)
        }
    }

    static func usd(_ x: Double) -> String {
        x < 1 ? String(format: "$%.3f", x) : String(format: "$%.2f", x)
    }

    static func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: d)
    }

    static func clockShort(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    /// "12s ago", "3m ago", "2h ago", absolute date past 24h.
    static func relative(_ d: Date) -> String {
        let s = -d.timeIntervalSinceNow
        if s < 5 { return "just now" }
        if s < 60 { return "\(Int(s))s ago" }
        if s < 3600 { return "\(Int(s/60))m ago" }
        if s < 86400 { return "\(Int(s/3600))h ago" }
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f.string(from: d)
    }
}
