import Foundation

/// On-disk cache so the app starts instantly instead of re-parsing every
/// JSONL file on every launch.
///
/// Persists to ~/Library/Application Support/TokenMeter/state.json:
///   - records:      all parsed UsageRecord objects (small: ~150 bytes each)
///   - fileOffsets:  per-file byte offset already consumed
///
/// File format is JSON for simplicity. For tens of thousands of records this
/// stays well under 10 MB on disk. If/when it grows, swap for SQLite without
/// changing the call sites.
struct PersistedState: Codable, Sendable {
    var records: [UsageRecord]
    var fileOffsets: [String: UInt64]   // path -> byte offset
    var version: Int

    static let currentVersion = 1
    static let empty = PersistedState(records: [], fileOffsets: [:], version: currentVersion)
}

final class StateStore: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var pendingFlush: DispatchWorkItem?
    private let queue = DispatchQueue(label: "TokenMeter.StateStore")

    init(url: URL = StateStore.defaultURL()) {
        self.url = url
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
    }

    static func defaultURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("TokenMeter", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    func load() -> PersistedState {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder.iso.decode(PersistedState.self, from: data),
              state.version == PersistedState.currentVersion
        else { return .empty }
        return state
    }

    /// Schedule a debounced write. Calls within 1 s are coalesced.
    func scheduleSave(_ state: PersistedState) {
        lock.lock()
        pendingFlush?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveNow(state)
        }
        pendingFlush = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    func saveNow(_ state: PersistedState) {
        lock.lock(); defer { lock.unlock() }
        do {
            let data = try JSONEncoder.iso.encode(state)
            let tmp = url.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            // Cache write failure is non-fatal; the next session will just re-parse.
        }
    }
}

private extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
private extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
