import Foundation
import CoreServices

/// Lightweight FSEvents wrapper. Coalesces changes within `debounce` and
/// reports the set of `.jsonl` URLs that touched.
final class ClaudeCodeWatcher: @unchecked Sendable {
    private let root: URL
    private let onChange: @Sendable (Set<URL>) -> Void
    private let queue = DispatchQueue(label: "TokenMeter.ClaudeCodeWatcher")
    private let debounce: TimeInterval
    private var stream: FSEventStreamRef?
    private var pending: Set<URL> = []
    private var debounceWorkItem: DispatchWorkItem?

    init(root: URL,
         debounce: TimeInterval = 0.4,
         onChange: @escaping @Sendable (Set<URL>) -> Void) {
        self.root = root
        self.debounce = debounce
        self.onChange = onChange
    }

    func start() {
        queue.async { self._start() }
    }

    func stop() {
        queue.async { self._stop() }
    }

    private func _start() {
        guard stream == nil else { return }
        let paths = [root.path] as CFArray
        let contextInfo = Unmanaged.passUnretained(self).toOpaque()
        var ctx = FSEventStreamContext(
            version: 0, info: contextInfo, retain: nil, release: nil, copyDescription: nil)
        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagFileEvents) |
            UInt32(kFSEventStreamCreateFlagNoDefer)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<ClaudeCodeWatcher>.fromOpaque(info).takeUnretainedValue()
            let cfArr = unsafeBitCast(paths, to: CFArray.self)
            let arr = (cfArr as? [String]) ?? []
            var jsonls: [URL] = []
            for s in arr where s.hasSuffix(".jsonl") {
                jsonls.append(URL(fileURLWithPath: s))
            }
            if !jsonls.isEmpty { watcher.enqueue(jsonls) }
            _ = count
        }
        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &ctx, paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2, flags) else { return }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    private func _stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    private func enqueue(_ urls: [URL]) {
        queue.async {
            for u in urls { self.pending.insert(u) }
            self.debounceWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let batch = self.pending
                self.pending.removeAll()
                if !batch.isEmpty { self.onChange(batch) }
            }
            self.debounceWorkItem = item
            self.queue.asyncAfter(deadline: .now() + self.debounce, execute: item)
        }
    }

    deinit { _stop() }
}
