import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        if let s = state.activeSession {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                MenuBarProgressBar(progress: pct(s), tint: state.status.tint)
                    .frame(width: 44, height: 7)
                Text(String.localizedStringWithFormat(
                    NSLocalizedString("menubar_session_tokens", comment: ""),
                    Format.tokens(s.totals.totalTokens)))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                trendArrow
            }
        } else {
            // No active session — fall back to today's volume as a book count.
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.0percent")
                Text(idleLabel)
                    .monospacedDigit()
                    .font(.system(size: 12, weight: .medium))
            }
        }
    }

    private func pct(_ s: SessionBlock) -> Double {
        min(1.0, Double(s.totals.totalTokens) / Double(max(1, state.sessionTokenBudget)))
    }

    /// Tiny direction arrow encoding current burn rate vs 7-day baseline.
    /// Hidden when there's no baseline yet (early in a session, or new install).
    @ViewBuilder
    private var trendArrow: some View {
        if let ratio = state.currentBurnRatio() {
            if ratio >= 1.5 {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.red)
            } else if ratio <= 0.66 {
                Image(systemName: "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
    }

    private var idleLabel: String {
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
}

/// Compact pill-shaped progress bar sized to fit on the system menu bar.
struct MenuBarProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule()
                    .fill(tint)
                    .frame(width: max(2, geo.size.width * progress))
            }
        }
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
        let status = state.statusDetail
        let level = status.level
        let session = state.activeSession
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: status.symbol)
                    .font(.title2).foregroundStyle(level.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.titleKey).font(.system(size: 15, weight: .semibold))
                    Text(status.bodyKey)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if let s = session {
                let used = s.totals.totalTokens
                let budget = max(1, state.sessionTokenBudget)
                let pct = min(1.0, Double(used) / Double(budget))
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.tokens(used)).font(.title3.monospacedDigit().bold())
                    Text("tokens").font(.caption).foregroundStyle(.secondary)
                    Text("·").font(.caption).foregroundStyle(.secondary)
                    Text("\(s.totals.messages) msg")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.clockShort(s.remaining))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Text("session_remaining_label")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: pct).tint(level.tint)
            }
            recencyLine
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    /// "방금 +5.2M 토큰 · 1분 전 업데이트" — only rendered when there's
    /// meaningful information (recent delta or last-updated within memory).
    @ViewBuilder
    private var recencyLine: some View {
        let delta = state.tokensAdded(inLastMinutes: 5)
        let updated = state.lastUpdated
        let isFresh = updated > .distantPast
        if isFresh || (delta ?? 0) > 0 {
            HStack(spacing: 6) {
                if let delta, delta > 10_000 {
                    Text(String.localizedStringWithFormat(
                        NSLocalizedString("delta_added", comment: ""),
                        Format.tokens(delta), 5))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(updatedLabel(updated))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func updatedLabel(_ d: Date) -> String {
        let s = -d.timeIntervalSinceNow
        if s < 10 { return NSLocalizedString("updated_just_now", comment: "") }
        return String.localizedStringWithFormat(
            NSLocalizedString("updated_relative", comment: ""),
            Format.relative(d))
    }

    private var todaySection: some View {
        let t = state.todayBucket?.totals ?? .init()
        let yesterday = state.yesterdayBucket?.totals
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
            if let y = yesterday, y.totalTokens > 0 {
                Text(String.localizedStringWithFormat(
                    NSLocalizedString("yesterday_was", comment: ""),
                    Format.tokens(y.totalTokens)))
                    .font(.caption2).foregroundStyle(.tertiary)
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
                Text("tokens").foregroundStyle(.secondary).font(.caption)
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
