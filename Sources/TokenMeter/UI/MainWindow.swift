import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers

struct MainWindow: View {
    @ObservedObject var state: AppState
    @StateObject private var launch = LaunchAtLogin()
    @State private var range: Range = .week
    @State private var groupBy: GroupBy = .model

    enum Range: String, CaseIterable, Identifiable {
        case week, twoWeeks, month
        var id: String { rawValue }
        var days: Int { self == .week ? 7 : (self == .twoWeeks ? 14 : 30) }
        var labelKey: LocalizedStringKey {
            switch self {
            case .week:     return "range_week"
            case .twoWeeks: return "range_two_weeks"
            case .month:    return "range_month"
            }
        }
    }
    enum GroupBy: String, CaseIterable, Identifiable {
        case model, project, tokenKind
        var id: String { rawValue }
        var labelKey: LocalizedStringKey {
            switch self {
            case .model:     return "group_model"
            case .project:   return "group_project"
            case .tokenKind: return "group_token_kind"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    folderAccessCardIfNeeded
                    HeroCard(state: state)
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
                    Picker("range", selection: $range) {
                        ForEach(Range.allCases) { Text($0.labelKey).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 260)
                }
                ToolbarItem(placement: .primaryAction) {
                    Picker("group", selection: $groupBy) {
                        ForEach(GroupBy.allCases) { Text($0.labelKey).tag($0) }
                    }.frame(width: 160)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("export_csv_visible") { export(.csv, days: range.days) }
                        Button("export_json_visible") { export(.json, days: range.days) }
                        Divider()
                        Button("export_csv_all") { export(.csv, days: nil) }
                        Button("export_json_all") { export(.json, days: nil) }
                    } label: {
                        Label("export", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle("app_name")
        }
        .frame(minWidth: 880, minHeight: 700)
    }

    // MARK: - Cards

    @ViewBuilder
    private var folderAccessCardIfNeeded: some View {
        if case .needsGrant = state.folderAccess.state {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .font(.title2).foregroundStyle(.orange)
                    Text("folder_grant_title").font(.headline)
                }
                Text("folder_grant_body").font(.callout).foregroundStyle(.secondary)
                Button {
                    Task { await state.requestClaudeFolderAccess() }
                } label: {
                    Label("folder_grant_button", systemImage: "folder.badge.plus")
                }
                .controlSize(.large)
            }
            .padding(16)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.5)))
        }
    }

    private var summaryCards: some View {
        let day = state.todayBucket?.totals ?? .init()
        let week = state.weekTotals
        let active = state.activeSession?.totals.totalTokens ?? 0
        return HStack(spacing: 12) {
            statCard(titleKey: "summary_today",
                     value: Format.tokens(day.totalTokens),
                     sub: Format.usd(day.costUSD), color: .orange)
            statCard(titleKey: "summary_this_week",
                     value: Format.tokens(week.totalTokens),
                     sub: Format.usd(week.costUSD), color: .blue)
            statCard(titleKey: "summary_active_session",
                     value: Format.tokens(active),
                     sub: state.activeSession.map { Format.clockShort($0.remaining) } ?? "—",
                     color: .green)
            statCard(titleKey: "summary_current_model",
                     value: state.currentModel.map(ModelCatalog.displayName) ?? "—",
                     sub: String.localizedStringWithFormat(
                        NSLocalizedString("messages_tracked", comment: ""), state.records.count),
                     color: .purple)
        }
    }

    private func statCard(titleKey: LocalizedStringKey, value: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleKey).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold().monospacedDigit())
            Text(sub).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.3)))
    }

    private var efficiencyCard: some View {
        let a = state.modelEfficiency(days: range.days)
        let pct = a.totalOpusMessages > 0
            ? Double(a.sonnetCandidateCount) / Double(a.totalOpusMessages)
            : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "scale.3d").foregroundStyle(.purple)
                Text(String.localizedStringWithFormat(
                    NSLocalizedString("efficiency_title", comment: ""), range.days))
                    .font(.headline)
                Spacer()
                Text(Format.usd(a.estimatedSavingsUSD))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(.green)
            }
            if a.totalOpusMessages == 0 {
                Text("efficiency_empty").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 16) {
                    statBlock(titleKey: "efficiency_opus_messages", value: "\(a.totalOpusMessages)")
                    statBlock(titleKey: "efficiency_sonnet_candidate", value: "\(a.sonnetCandidateCount)")
                    statBlock(titleKey: "efficiency_share", value: "\(Int(pct*100))%")
                }
                Text("efficiency_explainer").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func statBlock(titleKey: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(titleKey).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var chartCard: some View {
        let dailies = state.lastN(days: range.days)
        let groupLabel: String = {
            switch groupBy {
            case .model:     return NSLocalizedString("group_model", comment: "")
            case .project:   return NSLocalizedString("group_project", comment: "")
            case .tokenKind: return NSLocalizedString("group_token_kind", comment: "")
            }
        }()
        return VStack(alignment: .leading, spacing: 8) {
            Text(String.localizedStringWithFormat(
                NSLocalizedString("chart_title", comment: ""), groupLabel))
                .font(.headline)
            Chart {
                ForEach(dailies) { bucket in
                    switch groupBy {
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

    private var mcpCard: some View {
        let totals = state.mcpToolTotals(days: range.days)
        return VStack(alignment: .leading, spacing: 8) {
            Text(String.localizedStringWithFormat(
                NSLocalizedString("mcp_title", comment: ""), range.days))
                .font(.headline)
            HStack(spacing: 24) {
                mcpStat(icon: "magnifyingglass.circle.fill",
                        titleKey: "mcp_web_search",
                        value: totals.webSearch, color: .blue)
                mcpStat(icon: "arrow.down.circle.fill",
                        titleKey: "mcp_web_fetch",
                        value: totals.webFetch, color: .indigo)
                Spacer()
            }
            if totals.webSearch == 0 && totals.webFetch == 0 {
                Text("mcp_empty").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func mcpStat(icon: String, titleKey: LocalizedStringKey, value: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).font(.title2)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)").font(.title2.bold().monospacedDigit())
                Text(titleKey).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var topMessagesCard: some View {
        let top = state.topExpensive(days: range.days, limit: 10)
        return VStack(alignment: .leading, spacing: 8) {
            Text(String.localizedStringWithFormat(
                NSLocalizedString("top_messages_title", comment: ""), range.days))
                .font(.headline)
            if top.isEmpty {
                Text("top_messages_empty").foregroundStyle(.secondary).font(.caption)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("#").font(.caption).foregroundStyle(.secondary)
                        Text("col_when").font(.caption).foregroundStyle(.secondary)
                        Text("col_model").font(.caption).foregroundStyle(.secondary)
                        Text("col_project").font(.caption).foregroundStyle(.secondary)
                        Text("col_tokens").font(.caption).foregroundStyle(.secondary)
                        Text("col_cost").font(.caption).foregroundStyle(.secondary)
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
                Text(String.localizedStringWithFormat(
                    NSLocalizedString("projects_title", comment: ""), range.days))
                    .font(.headline)
                Spacer()
                let key = totals.count == 1 ? "projects_count_one" : "projects_count_other"
                Text(String.localizedStringWithFormat(
                    NSLocalizedString(key, comment: ""), totals.count))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if totals.isEmpty {
                Text("projects_empty").foregroundStyle(.secondary).font(.caption)
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
            Text("sessions_title").font(.headline)
            if sessions.isEmpty {
                Text("sessions_empty").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("col_started").font(.caption).foregroundStyle(.secondary)
                        Text("col_model").font(.caption).foregroundStyle(.secondary)
                        Text("col_tokens").font(.caption).foregroundStyle(.secondary)
                        Text("col_cost").font(.caption).foregroundStyle(.secondary)
                        Text("col_status").font(.caption).foregroundStyle(.secondary)
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
                                Label("session_active", systemImage: "circle.fill")
                                    .labelStyle(.titleAndIcon)
                                    .foregroundStyle(.green).font(.caption)
                            } else {
                                Text("session_done").foregroundStyle(.secondary).font(.caption)
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
            Text("settings_title").font(.headline)
            Text("settings_disclaimer").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("session_token_budget"); Spacer()
                BudgetField(value: $state.sessionTokenBudget)
            }
            HStack {
                Text("weekly_token_budget"); Spacer()
                BudgetField(value: $state.weeklyTokenBudget)
            }
            HStack {
                Text("session_message_budget"); Spacer()
                BudgetField(value: $state.sessionMessageBudget)
            }
            Divider().padding(.vertical, 2)
            Toggle("notify_thresholds", isOn: $state.notificationsEnabled)
            Divider().padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 2) {
                Toggle("launch_at_login", isOn: Binding(
                    get: { launch.isEnabled },
                    set: { launch.setEnabled($0) }
                ))
                Text(launch.statusDetail)
                    .font(.caption).foregroundStyle(.secondary)
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
