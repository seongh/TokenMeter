import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var state: AppState
    var body: some View {
        let today = state.todayBucket?.totals.totalTokens ?? 0
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.50percent")
            Text(Format.tokens(today))
                .monospacedDigit()
                .font(.system(size: 12, weight: .medium))
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
            todaySection
            Divider()
            activeSessionSection
            Divider()
            weeklySection
            Divider()
            providerBreakdown
            Divider()
            footer
        }
        .frame(width: 320)
        .padding(.vertical, 6)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("TokenMeter").font(.headline)
                Text("Universal AI token tracker")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if state.isLoading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Today", systemImage: "sun.max.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let m = state.currentModel {
                    Text(ModelCatalog.displayName(for: m))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            let t = state.todayBucket?.totals ?? .init()
            HStack(alignment: .firstTextBaseline) {
                Text(Format.tokens(t.totalTokens)).font(.title2.monospacedDigit().bold())
                Text("tokens").foregroundStyle(.secondary).font(.caption)
                Spacer()
                Text(Format.usd(t.costUSD)).foregroundStyle(.secondary).font(.caption.monospacedDigit())
            }
            TokenBreakdownBar(totals: t)
            HStack(spacing: 12) {
                tokenChip("in", t.input, .blue)
                tokenChip("cache W", t.cacheWrite, .purple)
                tokenChip("cache R", t.cacheRead, .teal)
                tokenChip("out", t.output, .pink)
            }.font(.caption2)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var activeSessionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Active 5h session", systemImage: "timer")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let s = state.activeSession {
                    Text("ends in \(Format.clockShort(s.remaining))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if let s = state.activeSession {
                let used = s.totals.totalTokens
                let budget = max(1, state.sessionTokenBudget)
                let pct = min(1.0, Double(used) / Double(budget))
                HStack {
                    Text(Format.tokens(used)).font(.title3.monospacedDigit().bold())
                    Text("/ \(Format.tokens(budget))")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(pct * 100))%").font(.caption.monospacedDigit())
                }
                ProgressView(value: pct).tint(pct > 0.85 ? .red : .accentColor)
            } else {
                Text("No active session").foregroundStyle(.secondary).font(.caption)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Last 7 days", systemImage: "calendar")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(Format.usd(state.weekTotals.costUSD))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            let used = state.weekTotals.totalTokens
            let budget = max(1, state.weeklyTokenBudget)
            let pct = min(1.0, Double(used) / Double(budget))
            HStack {
                Text(Format.tokens(used)).font(.title3.monospacedDigit().bold())
                Text("/ \(Format.tokens(budget))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(pct * 100))%").font(.caption.monospacedDigit())
            }
            ProgressView(value: pct).tint(pct > 0.85 ? .red : .green)
            MiniWeeklyBars(buckets: state.lastN(days: 7))
                .frame(height: 28)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var providerBreakdown: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Providers", systemImage: "square.stack.3d.up")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            ForEach(state.totalsByProvider, id: \.0) { provider, t in
                HStack(spacing: 6) {
                    Circle().fill(provider.color).frame(width: 8, height: 8)
                    Text(provider.displayName).font(.caption)
                    if let s = state.providerStatuses[provider] {
                        Image(systemName: s.iconName)
                            .font(.caption2)
                            .foregroundStyle(statusColor(s))
                    }
                    Spacer()
                    Text(Format.tokens(t.totalTokens))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if state.totalsByProvider.isEmpty {
                Text("No data yet").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func statusColor(_ s: ProviderStatus) -> Color {
        switch s {
        case .ok: return .green
        case .syncing: return .secondary
        case .error: return .red
        case .idle: return .secondary
        }
    }

    private var footer: some View {
        HStack {
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open dashboard", systemImage: "chart.bar.xaxis")
            }
            .buttonStyle(.borderless)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .keyboardShortcut("q")
        }
        .font(.caption)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func tokenChip(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label) \(Format.tokens(value))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

struct TokenBreakdownBar: View {
    let totals: BucketTotals
    var body: some View {
        GeometryReader { geo in
            let total = max(1, totals.totalTokens)
            HStack(spacing: 1) {
                Rectangle().fill(Color.blue)
                    .frame(width: geo.size.width * CGFloat(totals.input)/CGFloat(total))
                Rectangle().fill(Color.purple)
                    .frame(width: geo.size.width * CGFloat(totals.cacheWrite)/CGFloat(total))
                Rectangle().fill(Color.teal)
                    .frame(width: geo.size.width * CGFloat(totals.cacheRead)/CGFloat(total))
                Rectangle().fill(Color.pink)
                    .frame(width: geo.size.width * CGFloat(totals.output)/CGFloat(total))
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
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
