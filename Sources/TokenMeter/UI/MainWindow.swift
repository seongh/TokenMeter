import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers

struct MainWindow: View {
    @ObservedObject var state: AppState
    @StateObject private var launch = LaunchAtLogin()
    @State private var range: Range = .week
    @State private var groupBy: GroupBy = .provider

    enum Range: String, CaseIterable, Identifiable {
        case week = "Week", twoWeeks = "2 Weeks", month = "Month"
        var id: String { rawValue }
        var days: Int { self == .week ? 7 : (self == .twoWeeks ? 14 : 30) }
    }
    enum GroupBy: String, CaseIterable, Identifiable {
        case provider = "Provider", model = "Model", project = "Project", tokenKind = "Token kind"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    folderAccessCardIfNeeded
                    summaryCards
                    efficiencyCard
                    chartCard
                    mcpCard
                    projectCard
                    topMessagesCard
                    sessionsCard
                    settingsCard
                }
                .padding(20)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Range", selection: $range) {
                        ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 260)
                }
                ToolbarItem(placement: .primaryAction) {
                    Picker("Group", selection: $groupBy) {
                        ForEach(GroupBy.allCases) { Text($0.rawValue).tag($0) }
                    }.frame(width: 160)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Export visible range as CSV") { export(.csv, days: range.days) }
                        Button("Export visible range as JSON") { export(.json, days: range.days) }
                        Divider()
                        Button("Export ALL records as CSV") { export(.csv, days: nil) }
                        Button("Export ALL records as JSON") { export(.json, days: nil) }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle("TokenMeter")
        }
        .frame(minWidth: 820, minHeight: 600)
    }

    // MARK: - Cards

    private var summaryCards: some View {
        let day = state.todayBucket?.totals ?? .init()
        let week = state.weekTotals
        let active = state.activeSession?.totals.totalTokens ?? 0
        return HStack(spacing: 12) {
            statCard(title: "Today",
                     value: Format.tokens(day.totalTokens),
                     sub: Format.usd(day.costUSD), color: .orange)
            statCard(title: "This week",
                     value: Format.tokens(week.totalTokens),
                     sub: Format.usd(week.costUSD), color: .blue)
            statCard(title: "Active session",
                     value: Format.tokens(active),
                     sub: state.activeSession.map { "ends in " + Format.clockShort($0.remaining) } ?? "—",
                     color: .green)
            statCard(title: "Current model",
                     value: state.currentModel.map(ModelCatalog.displayName) ?? "—",
                     sub: "\(state.records.count) messages tracked",
                     color: .purple)
        }
    }

    private func statCard(title: String, value: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold().monospacedDigit())
            Text(sub).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.3)))
    }

    private var chartCard: some View {
        let dailies = state.lastN(days: range.days)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Daily tokens — grouped by \(groupBy.rawValue.lowercased())")
                .font(.headline)
            Chart {
                ForEach(dailies) { bucket in
                    switch groupBy {
                    case .provider:
                        ForEach(Array(bucket.byProvider.keys.sorted { $0.rawValue < $1.rawValue }), id: \.self) { p in
                            BarMark(
                                x: .value("Day", bucket.date, unit: .day),
                                y: .value("Tokens", bucket.byProvider[p]?.totalTokens ?? 0)
                            )
                            .foregroundStyle(by: .value("Provider", p.displayName))
                        }
                    case .model:
                        ForEach(Array(bucket.byModel.keys.sorted()), id: \.self) { m in
                            BarMark(
                                x: .value("Day", bucket.date, unit: .day),
                                y: .value("Tokens", bucket.byModel[m]?.totalTokens ?? 0)
                            )
                            .foregroundStyle(by: .value("Model", m))
                        }
                    case .project:
                        ForEach(Array(bucket.byProject.keys.sorted()), id: \.self) { p in
                            BarMark(
                                x: .value("Day", bucket.date, unit: .day),
                                y: .value("Tokens", bucket.byProject[p]?.totalTokens ?? 0)
                            )
                            .foregroundStyle(by: .value("Project", p))
                        }
                    case .tokenKind:
                        BarMark(x: .value("Day", bucket.date, unit: .day),
                                y: .value("Tokens", bucket.totals.input))
                            .foregroundStyle(by: .value("Kind", "Input"))
                        BarMark(x: .value("Day", bucket.date, unit: .day),
                                y: .value("Tokens", bucket.totals.cacheWrite))
                            .foregroundStyle(by: .value("Kind", "Cache write"))
                        BarMark(x: .value("Day", bucket.date, unit: .day),
                                y: .value("Tokens", bucket.totals.cacheRead))
                            .foregroundStyle(by: .value("Kind", "Cache read"))
                        BarMark(x: .value("Day", bucket.date, unit: .day),
                                y: .value("Tokens", bucket.totals.output))
                            .foregroundStyle(by: .value("Kind", "Output"))
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 280)
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var folderAccessCardIfNeeded: some View {
        if case .needsGrant = state.folderAccess.state {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .font(.title2).foregroundStyle(.orange)
                    Text("Grant access to your Claude logs folder")
                        .font(.headline)
                }
                Text("TokenMeter is running inside the macOS App Sandbox and cannot read **~/.claude/projects** until you explicitly allow it. The permission is read-only and persists across launches.")
                    .font(.callout).foregroundStyle(.secondary)
                Button {
                    Task { await state.requestClaudeFolderAccess() }
                } label: {
                    Label("Choose Claude folder…", systemImage: "folder.badge.plus")
                }
                .controlSize(.large)
            }
            .padding(16)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.5)))
        }
    }

    private var efficiencyCard: some View {
        let a = state.modelEfficiency(days: range.days)
        let pct = a.totalOpusMessages > 0
            ? Double(a.sonnetCandidateCount) / Double(a.totalOpusMessages)
            : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "scale.3d").foregroundStyle(.purple)
                Text("Model efficiency — last \(range.days) days").font(.headline)
                Spacer()
                Text(Format.usd(a.estimatedSavingsUSD))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(.green)
            }
            if a.totalOpusMessages == 0 {
                Text("No Opus messages in this window — nothing to analyze.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 16) {
                    statBlock(title: "Opus messages", value: "\(a.totalOpusMessages)")
                    statBlock(title: "Sonnet-candidate", value: "\(a.sonnetCandidateCount)")
                    statBlock(title: "Share", value: "\(Int(pct*100))%")
                }
                Text("Heuristic: an Opus message is flagged as a Sonnet-candidate when its prompt + output were both small enough that Sonnet 4.6 would probably have produced an equivalent answer. The number on the right is your estimated cost saving if those messages had run on Sonnet instead. **This is a guess, not a recommendation** — Opus is genuinely better for complex reasoning even on short prompts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func statBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var mcpCard: some View {
        let totals = state.mcpToolTotals(days: range.days)
        return VStack(alignment: .leading, spacing: 8) {
            Text("MCP server-side tools — last \(range.days) days").font(.headline)
            HStack(spacing: 24) {
                mcpStat(icon: "magnifyingglass.circle.fill",
                        title: "Web search calls",
                        value: totals.webSearch, color: .blue)
                mcpStat(icon: "arrow.down.circle.fill",
                        title: "Web fetch calls",
                        value: totals.webFetch, color: .indigo)
                Spacer()
            }
            if totals.webSearch == 0 && totals.webFetch == 0 {
                Text("No server-side tool calls recorded in this window.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func mcpStat(icon: String, title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).font(.title2)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)").font(.title2.bold().monospacedDigit())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var topMessagesCard: some View {
        let top = state.topExpensive(days: range.days, limit: 10)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Top 10 most expensive messages — last \(range.days) days")
                .font(.headline)
            if top.isEmpty {
                Text("Nothing in this window yet").foregroundStyle(.secondary).font(.caption)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("#").font(.caption).foregroundStyle(.secondary)
                        Text("When").font(.caption).foregroundStyle(.secondary)
                        Text("Model").font(.caption).foregroundStyle(.secondary)
                        Text("Project").font(.caption).foregroundStyle(.secondary)
                        Text("Tokens").font(.caption).foregroundStyle(.secondary)
                        Text("Cost").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    ForEach(Array(top.enumerated()), id: \.element.id) { idx, r in
                        GridRow {
                            Text("\(idx + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text(r.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption.monospacedDigit())
                            Text(ModelCatalog.displayName(for: r.model)).font(.caption)
                            Text(r.project ?? "—").font(.caption)
                                .lineLimit(1).truncationMode(.middle)
                            Text(Format.tokens(r.totalTokens)).font(.caption.monospacedDigit())
                            Text(r.costUSD.map(Format.usd) ?? "—").font(.caption.monospacedDigit())
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var projectCard: some View {
        let totals = state.projectTotals(days: range.days)
        let maxV = max(1, totals.first?.totals.totalTokens ?? 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Top projects — last \(range.days) days").font(.headline)
                Spacer()
                Text("\(totals.count) project\(totals.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if totals.isEmpty {
                Text("No Claude Code projects tracked yet")
                    .foregroundStyle(.secondary).font(.caption)
            } else {
                VStack(spacing: 6) {
                    ForEach(totals.prefix(8), id: \.name) { entry in
                        ProjectRow(name: entry.name, totals: entry.totals, maxTokens: maxV)
                    }
                }
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var sessionsCard: some View {
        let sessions = state.sessions.suffix(10).reversed() as [SessionBlock]
        return VStack(alignment: .leading, spacing: 8) {
            Text("Recent 5h session blocks").font(.headline)
            if sessions.isEmpty {
                Text("No sessions tracked yet").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("Started").font(.caption).foregroundStyle(.secondary)
                        Text("Model").font(.caption).foregroundStyle(.secondary)
                        Text("Tokens").font(.caption).foregroundStyle(.secondary)
                        Text("Cost").font(.caption).foregroundStyle(.secondary)
                        Text("Status").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    ForEach(sessions, id: \.startedAt) { s in
                        GridRow {
                            Text(s.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption.monospacedDigit())
                            Text(s.primaryModel.map(ModelCatalog.displayName) ?? "—").font(.caption)
                            Text(Format.tokens(s.totals.totalTokens)).font(.caption.monospacedDigit())
                            Text(Format.usd(s.totals.costUSD)).font(.caption.monospacedDigit())
                            if s.isActive {
                                Label("active", systemImage: "circle.fill")
                                    .labelStyle(.titleAndIcon)
                                    .foregroundStyle(.green).font(.caption)
                            } else {
                                Text("done").foregroundStyle(.secondary).font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Budgets & Notifications").font(.headline)
            Text("These don't reflect real plan limits (Anthropic doesn't expose them). They're targets so the bars are meaningful.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Session token budget")
                Spacer()
                BudgetField(value: $state.sessionTokenBudget)
            }
            HStack {
                Text("Weekly token budget")
                Spacer()
                BudgetField(value: $state.weeklyTokenBudget)
            }
            HStack {
                Text("Session message budget")
                Spacer()
                BudgetField(value: $state.sessionMessageBudget)
            }
            Divider().padding(.vertical, 2)
            Toggle("Notify at 80% / 95% of session budget", isOn: $state.notificationsEnabled)
            Divider().padding(.vertical, 2)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Launch TokenMeter at login", isOn: Binding(
                        get: { launch.isEnabled },
                        set: { launch.setEnabled($0) }
                    ))
                    Text(launch.statusDetail)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func export(_ format: Exporter.Format, days: Int?) {
        let data = state.exportData(format: format, days: days)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format == .csv ? .commaSeparatedText : .json]
        let date = Date().formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "tokenmeter-\(date).\(format.fileExtension)"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }
}

struct ProjectRow: View {
    let name: String
    let totals: BucketTotals
    let maxTokens: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(displayName).font(.body)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(Format.tokens(totals.totalTokens))
                    .font(.body.monospacedDigit())
                Text(Format.usd(totals.costUSD))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
            GeometryReader { geo in
                let w = geo.size.width * CGFloat(totals.totalTokens) / CGFloat(max(1, maxTokens))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(Color.accentColor.opacity(0.7))
                        .frame(width: max(2, w))
                }
            }
            .frame(height: 6)
        }
    }

    /// Strip the URL-encoded `-Users-seongho-Documents-…` prefix to the last segment.
    private var displayName: String {
        guard name != "unattributed" else { return name }
        let trimmed = name.hasPrefix("-") ? String(name.dropFirst()) : name
        return trimmed.split(separator: "-").suffix(2).joined(separator: "/")
    }
}

struct BudgetField: View {
    @Binding var value: Int
    var body: some View {
        TextField("", value: $value, format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 160)
            .monospacedDigit()
    }
}
