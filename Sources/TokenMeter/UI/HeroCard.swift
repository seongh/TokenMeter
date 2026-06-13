import SwiftUI

/// Single big card at the top of the dashboard. Communicates "how am I doing
/// right now" in one glance: status word + color + one secondary metric.
struct HeroCard: View {
    @ObservedObject var state: AppState

    var body: some View {
        let level = state.status
        let session = state.activeSession
        let used = session?.totals.totalTokens ?? state.todayBucket?.totals.totalTokens ?? 0
        let budget = max(1, state.sessionTokenBudget)
        let pct = session.map { min(1.0, Double($0.totals.totalTokens) / Double(budget)) } ?? 0

        return VStack(alignment: .leading, spacing: 14) {
            // Status headline
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: level.symbol)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(level.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.titleKey)
                        .font(.system(size: 26, weight: .bold))
                    Text(level.bodyKey)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let s = session {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Format.clockShort(s.remaining))
                            .font(.system(size: 24, weight: .semibold).monospacedDigit())
                        Text("session_remaining_label")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            // Key metrics row
            HStack(spacing: 24) {
                metric(value: Format.tokens(used), labelKey: "tokens")
                if let s = session {
                    metric(value: "\(s.totals.messages)", labelKey: "messages")
                }
                if let ratio = state.currentBurnRatio() {
                    paceMetric(ratio: ratio)
                }
                Spacer()
            }

            // Progress bar (only when there's a session)
            if session != nil {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: pct)
                        .tint(level.tint)
                        .scaleEffect(x: 1, y: 1.4, anchor: .center)
                    HStack {
                        Text("\(Format.tokens(used)) / \(Format.tokens(budget))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(pct * 100))%")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(level.tint.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(level.tint.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private func metric(value: String, labelKey: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.bold().monospacedDigit())
            Text(labelKey).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func paceMetric(ratio: Double) -> some View {
        let labelKey: LocalizedStringKey
        let displayRatio: Double
        if ratio >= 1.15 {
            labelKey = LocalizedStringKey("pace_faster")
            displayRatio = ratio
        } else if ratio <= 0.85 {
            labelKey = LocalizedStringKey("pace_slower")
            displayRatio = 1.0 / ratio
        } else {
            labelKey = LocalizedStringKey("pace_normal")
            displayRatio = 1.0
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.1f×", displayRatio))
                .font(.title2.bold().monospacedDigit())
            Text(labelKey).font(.caption).foregroundStyle(.secondary)
        }
    }
}
