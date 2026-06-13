import Foundation

enum Format {
    private static var bundleLanguage: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }
    private static var isKorean: Bool { bundleLanguage.hasPrefix("ko") }

    /// 1,234,567 -> "1.23M". Korean variant: "123만".
    static func tokens(_ n: Int) -> String {
        let abs = Swift.abs(n)
        if isKorean {
            switch abs {
            case ..<1_000:           return "\(n)"
            case ..<10_000:          return String(format: "%.1f천", Double(n)/1_000)
            case ..<100_000_000:     return "\(n / 10_000)만"
            default:                 return String(format: "%.1f억", Double(n)/100_000_000)
            }
        } else {
            switch abs {
            case ..<1_000:           return "\(n)"
            case ..<1_000_000:       return String(format: "%.1fK", Double(n)/1_000)
            case ..<1_000_000_000:   return String(format: "%.2fM", Double(n)/1_000_000)
            default:                 return String(format: "%.2fB", Double(n)/1_000_000_000)
            }
        }
    }

    static func usd(_ x: Double) -> String {
        x < 1 ? String(format: "$%.3f", x) : String(format: "$%.2f", x)
    }

    static func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = isKorean ? "M월 d일" : "M/d"
        return f.string(from: d)
    }

    /// "1h 42m" / "1시간 42분".
    static func clockShort(_ interval: TimeInterval) -> String {
        let h = Int(interval) / 3600
        let m = (Int(interval) % 3600) / 60
        if isKorean {
            if h > 0 {
                let template = NSLocalizedString("time_hours_minutes", comment: "")
                return String.localizedStringWithFormat(template, h, m)
            }
            let template = NSLocalizedString("time_minutes_only", comment: "")
            return String.localizedStringWithFormat(template, m)
        }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    /// "12s ago" / "방금 전" / "3분 전".
    static func relative(_ d: Date) -> String {
        let s = Int(-d.timeIntervalSinceNow)
        if s < 5 {
            return NSLocalizedString("relative_just_now", comment: "")
        }
        if s < 60 {
            return String.localizedStringWithFormat(
                NSLocalizedString("relative_seconds", comment: ""), s)
        }
        if s < 3600 {
            return String.localizedStringWithFormat(
                NSLocalizedString("relative_minutes", comment: ""), s / 60)
        }
        if s < 86400 {
            return String.localizedStringWithFormat(
                NSLocalizedString("relative_hours", comment: ""), s / 3600)
        }
        let f = DateFormatter()
        f.dateFormat = isKorean ? "M월 d일 HH:mm" : "M/d HH:mm"
        return f.string(from: d)
    }
}
