import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var state: AppState
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
            Text(labelText)
                .monospacedDigit()
                .font(.system(size: 12, weight: .medium))
        }
    }

    /// Active session: "1시간 50분 남음" / "1h 50m left".
    /// No session: "오늘 ≈ 책 1,100권" / "Today ≈ 1100 books".
    /// The icon's color already encodes the burn level, so the label is just
    /// the single piece of information you need to decide whether to act.
    private var labelText: String {
        if let s = state.activeSession {
            return String.localizedStringWithFormat(
                NSLocalizedString("menubar_time_left", comment: ""),
                Format.clockShort(s.remaining))
        }
        let tokens = state.todayBucket?.totals.totalTokens ?? 0
        if tokens >= 100_000 {
            let books = tokens / 100_000
            return String.localizedStringWithFormat(
                NSLocalizedString("menubar_today_books", comment: ""), books)
        }
        return String.localizedStringWithFormat(
            NSLocalizedString("menubar_today_tokens", comment: ""),
            Format.tokens(tokens))
    }

    private var iconName: String {
        guard let s = state.activeSession else { return "gauge.with.dots.needle.0percent" }
        let pct = Double(s.totals.totalTokens) / Double(max(1, state.sessionTokenBudget))
        if pct >= 0.95 { return "gauge.with.dots.needle.100percent" }
        if pct >= 0.66 { return "gauge.with.dots.needle.67percent" }
        if pct >= 0.33 { return "gauge.with.dots.needle.50percent" }
        return "gauge.with.dots.needle.33percent"
    }
}

struct MenuBarContent: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            statusSection
            Divider()
            todaySection
            Divider()
            weeklySection
            Divider()
            footer
        }
        .frame(width: 340)
        .padding(.vertical, 6)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("app_name").font(.headline)
                Text("tagline")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if state.isLoading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
    }

    private var statusSection: some View {
        let level = state.status
        let session = state.activeSession
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: level.symbol)
                    .font(.title2).foregroundStyle(level.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(level.titleKey).font(.system(size: 15, weight: .semibold))
                    Text(level.bodyKey).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let s = session {
                let used = s.totals.totalTokens
                let budget = max(1, state.sessionTokenBudget)
                let pct = min(1.0, Double(used) / Double(budget))
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.clockShort(s.remaining))
                        .font(.title3.monospacedDigit().bold())
                    Text("session_remaining_label").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Format.tokens(used)) · \(s.totals.messages) msg")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                ProgressView(value: pct).tint(level.tint)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var todaySection: some View {
        let t = state.todayBucket?.totals ?? .init()
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("today", systemImage: "sun.max.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let m = state.currentModel {
                    Text(ModelCatalog.displayName(for: m))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(Format.tokens(t.totalTokens)).font(.title2.monospacedDigit().bold())
                Text("tokens").foregroundStyle(.secondary).font(.caption)
                Spacer()
                Text(Format.usd(t.costUSD)).foregroundStyle(.secondary).font(.caption.monospacedDigit())
            }
            if let hint = Format.humanizedTokens(t.totalTokens) {
                Text(hint).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("this_week", systemImage: "calendar")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(Format.usd(state.weekTotals.costUSD))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(Format.tokens(state.weekTotals.totalTokens))
                    .font(.title3.monospacedDigit().bold())
                Spacer()
                Text("\(state.weekTotals.messages) msg")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let hint = Format.humanizedTokens(state.weekTotals.totalTokens) {
                Text(hint).font(.caption2).foregroundStyle(.tertiary)
            }
            MiniWeeklyBars(buckets: state.lastN(days: 7))
                .frame(height: 28)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("open_dashboard", systemImage: "chart.bar.xaxis")
            }
            .buttonStyle(.borderless)
            Spacer()
            Button("quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .keyboardShortcut("q")
        }
        .font(.caption)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}

struct MiniWeeklyBars: View {
    let buckets: [DailyBucket]
    var body: some View {
        GeometryReader { geo in
            let maxV = max(1, buckets.map { $0.totals.totalTokens }.max() ?? 1)
            let n = max(1, buckets.count)
            let w = (geo.size.width - CGFloat(n - 1) * 3) / CGFloat(n)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(buckets) { b in
                    let h = geo.size.height * CGFloat(b.totals.totalTokens) / CGFloat(maxV)
                    VStack(spacing: 2) {
                        Spacer()
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(0.7))
                            .frame(width: w, height: max(2, h))
                    }
                }
            }
        }
    }
}
