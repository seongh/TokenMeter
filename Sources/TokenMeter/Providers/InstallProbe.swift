import Foundation

/// Read-only directory probe. Detects whether other AI tools are installed
/// without reading their private state (which is often locked or contains
/// credentials). We surface presence so the dashboard can show
/// "Cursor detected — vendor doesn't expose token data".
enum InstallProbe {
    struct Detection: Sendable, Hashable, Identifiable {
        let provider: Provider
        let name: String
        let path: String
        let dataExposed: Bool         // false = vendor doesn't publish token data
        let note: String
        var id: String { name }
    }

    static func probeAll() -> [Detection] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let appSupport = home.appendingPathComponent("Library/Application Support")
        let candidates: [(name: String, dir: String, provider: Provider, note: String)] = [
            ("Cursor",   "Cursor",   .cursor,
             "Cursor stores chat logs in a private SQLite DB but does not expose per-message token counts."),
            ("Windsurf", "Windsurf", .other,
             "Windsurf does not publish a local token usage stream."),
            ("Codeium",  "Codeium",  .other,
             "Codeium does not publish a local token usage stream.")
        ]
        var out: [Detection] = []
        for c in candidates {
            let url = appSupport.appendingPathComponent(c.dir, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                out.append(.init(
                    provider: c.provider,
                    name: c.name,
                    path: url.path,
                    dataExposed: false,
                    note: c.note))
            }
        }
        return out
    }
}
