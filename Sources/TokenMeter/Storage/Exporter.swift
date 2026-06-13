import Foundation

/// Turns `[UsageRecord]` into CSV or JSON for accounting/analysis.
enum Exporter {
    enum Format: String, CaseIterable, Identifiable {
        case csv = "CSV", json = "JSON"
        var id: String { rawValue }
        var fileExtension: String { self == .csv ? "csv" : "json" }
        var utiPreferredFilenameExtension: String { fileExtension }
    }

    static func render(_ records: [UsageRecord], as format: Format) -> Data {
        switch format {
        case .csv:  return csv(records).data(using: .utf8) ?? Data()
        case .json: return (try? jsonEncoder.encode(records)) ?? Data()
        }
    }

    static func csv(_ records: [UsageRecord]) -> String {
        let header = [
            "timestamp", "provider", "model", "project", "session_id",
            "input_tokens", "cache_creation_tokens", "cache_read_tokens",
            "output_tokens", "total_tokens", "cost_usd",
            "web_search_requests", "web_fetch_requests"
        ].joined(separator: ",")

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        var lines: [String] = [header]
        for r in records {
            let row: [String] = [
                iso.string(from: r.timestamp),
                r.provider.rawValue,
                escape(r.model),
                escape(r.project ?? ""),
                escape(r.sessionId ?? ""),
                String(r.inputTokens),
                String(r.cacheCreationTokens),
                String(r.cacheReadTokens),
                String(r.outputTokens),
                String(r.totalTokens),
                r.costUSD.map { String(format: "%.6f", $0) } ?? "",
                String(r.webSearchRequests ?? 0),
                String(r.webFetchRequests ?? 0)
            ]
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ s: String) -> String {
        guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
        let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static var jsonEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
