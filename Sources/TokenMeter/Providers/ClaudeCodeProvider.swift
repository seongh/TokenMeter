import Foundation

/// Reads ~/.claude/projects/*/*.jsonl. Each assistant message line has the
/// shape { type:"assistant", message:{model, usage:{...}}, timestamp, ... }.
/// File names encode the source workspace path.
final class ClaudeCodeProvider: UsageProvider, @unchecked Sendable {
    let provider: Provider = .claudeCode

    private var root: URL?                        // nil = no folder granted yet
    private let lock = NSLock()
    private var fileOffsets: [URL: UInt64] = [:]    // resume parsing from here
    private var seen: Set<String> = []              // dedupe by message uuid

    init(root: URL? = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects"),
         initialOffsets: [String: UInt64] = [:],
         seenIDs: Set<String> = []) {
        self.root = root
        for (path, off) in initialOffsets {
            fileOffsets[URL(fileURLWithPath: path)] = off
        }
        self.seen = seenIDs
    }

    /// Swap the root folder at runtime — used after the user grants access in
    /// the sandboxed build via NSOpenPanel.
    func updateRoot(_ url: URL?) {
        withLock { self.root = url }
    }

    /// Current per-file byte offsets, keyed by absolute path. Used by the cache layer.
    func currentOffsets() -> [String: UInt64] {
        withLock {
            var out: [String: UInt64] = [:]
            for (url, off) in fileOffsets { out[url.path] = off }
            return out
        }
    }

    func testConnection() async throws -> TestResult {
        guard let root = withLock({ self.root }) else {
            return TestResult(
                recordsReachable: 0,
                detail: "No Claude logs folder granted (sandbox: needs user permission).")
        }
        let files = (try? Self.discoverJSONL(under: root)) ?? []
        return TestResult(
            recordsReachable: files.count,
            detail: files.isEmpty
                ? "No Claude Code log files found at \(root.path)."
                : "Found \(files.count) Claude Code log files at \(root.path)."
        )
    }

    /// Re-seed parser state from persisted cache.
    func seed(offsets: [String: UInt64], seenIDs: Set<String>) {
        withLock {
            for (path, off) in offsets {
                fileOffsets[URL(fileURLWithPath: path)] = off
            }
            seen.formUnion(seenIDs)
        }
    }

    func snapshot() async throws -> [UsageRecord] {
        guard let root = withLock({ self.root }) else { return [] }
        return try await Task.detached(priority: .utility) { [self] in
            let files = try Self.discoverJSONL(under: root)
            var all: [UsageRecord] = []
            for file in files {
                let from = self.withLock { self.fileOffsets[file] ?? 0 }
                all.append(contentsOf: try self.parse(file: file, fromOffset: from))
            }
            return all
        }.value
    }

    func live() -> AsyncStream<[UsageRecord]> {
        AsyncStream { continuation in
            guard let root = self.withLock({ self.root }) else {
                continuation.finish(); return
            }
            let watcher = ClaudeCodeWatcher(root: root) { [weak self] changed in
                guard let self else { return }
                var delta: [UsageRecord] = []
                for url in changed {
                    let off = self.withLock { self.fileOffsets[url] ?? 0 }
                    if let new = try? self.parse(file: url, fromOffset: off) {
                        delta.append(contentsOf: new)
                    }
                }
                if !delta.isEmpty { continuation.yield(delta) }
            }
            watcher.start()
            continuation.onTermination = { _ in watcher.stop() }
        }
    }

    // MARK: - File discovery

    static func discoverJSONL(under root: URL) throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root,
                                             includingPropertiesForKeys: [.isRegularFileKey],
                                             options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            out.append(url)
        }
        return out
    }

    // MARK: - Parse

    func parse(file: URL, fromOffset: UInt64) throws -> [UsageRecord] {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: fromOffset)
        let data = handle.readDataToEndOfFile()

        let project = decodedProject(file.deletingLastPathComponent().lastPathComponent)

        var out: [UsageRecord] = []
        var consumed: Int = 0
        var newlySeen: [String] = []

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            var lineStart = 0
            for i in 0..<data.count {
                if base[i] == 0x0A { // \n
                    let len = i - lineStart
                    if len > 0 {
                        let lineData = Data(bytes: base + lineStart, count: len)
                        if let rec = try? Self.parseLine(lineData, project: project) {
                            let inserted = withLock { seen.insert(rec.id).inserted }
                            if inserted {
                                out.append(rec)
                                newlySeen.append(rec.id)
                            }
                        }
                    }
                    lineStart = i + 1
                    consumed = i + 1
                }
            }
        }
        withLock {
            fileOffsets[file] = fromOffset + UInt64(consumed)
        }
        return out
    }

    private func decodedProject(_ name: String) -> String {
        let trimmed = name.hasPrefix("-") ? String(name.dropFirst()) : name
        return trimmed.split(separator: "-").last.map(String.init) ?? name
    }

    static func parseLine(_ data: Data, project: String?) throws -> UsageRecord? {
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let type = raw["type"] as? String, type == "assistant" else { return nil }
        guard let message = raw["message"] as? [String: Any] else { return nil }
        guard let usage = message["usage"] as? [String: Any] else { return nil }

        let model = (message["model"] as? String) ?? "unknown"
        let uuid = (raw["uuid"] as? String) ?? UUID().uuidString
        let sessionId = raw["sessionId"] as? String
        let ts = (raw["timestamp"] as? String).flatMap(parseISO8601) ?? Date()

        let input = (usage["input_tokens"] as? Int) ?? 0
        let cacheW = (usage["cache_creation_input_tokens"] as? Int) ?? 0
        let cacheR = (usage["cache_read_input_tokens"] as? Int) ?? 0
        let output = (usage["output_tokens"] as? Int) ?? 0

        let serverTool = usage["server_tool_use"] as? [String: Any]
        let webSearch = serverTool?["web_search_requests"] as? Int
        let webFetch  = serverTool?["web_fetch_requests"] as? Int

        let cost = ModelCatalog.match(model)?.costUSD(
            input: input, cacheWrite: cacheW, cacheRead: cacheR, output: output)

        return UsageRecord(
            id: uuid,
            provider: .claudeCode,
            model: model,
            timestamp: ts,
            inputTokens: input,
            cacheCreationTokens: cacheW,
            cacheReadTokens: cacheR,
            outputTokens: output,
            sessionId: sessionId,
            project: project,
            costUSD: cost,
            webSearchRequests: webSearch,
            webFetchRequests: webFetch
        )
    }

    @discardableResult
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
}

fileprivate func parseISO8601(_ s: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)
}
