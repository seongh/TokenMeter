import Foundation
import AppKit

/// Manages access to the Claude Code logs folder under the App Sandbox.
///
/// Outside the sandbox we can read `~/.claude/projects` directly. Inside the
/// sandbox (Mac App Store builds) the user must explicitly grant access via
/// an NSOpenPanel; we then persist a security-scoped bookmark in UserDefaults
/// so the choice survives relaunch.
@MainActor
final class ClaudeFolderAccess: ObservableObject {
    enum State: Equatable {
        case granted(URL)        // resolved URL with access started
        case needsGrant          // sandbox active + no/stale bookmark
        case unsandboxed(URL)    // direct filesystem access (dev builds)
    }

    @Published private(set) var state: State

    /// Whether we appear to be running under the App Sandbox.
    /// Inside the sandbox NSHomeDirectory() points at the per-app container
    /// (~/Library/Containers/<bundle-id>/Data), not the real user home — that's
    /// the most reliable signal across macOS versions.
    static var isSandboxed: Bool {
        NSHomeDirectory().contains("/Library/Containers/")
    }

    private static let bookmarkKey = "claudeFolderBookmark"
    /// Tracks the active security scope so we stop accessing on shutdown.
    private var activeScopedURL: URL?

    init() {
        let defaultDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        if !Self.isSandboxed {
            // Dev/distribution outside the App Sandbox: read directly.
            self.state = .unsandboxed(defaultDir)
            return
        }

        if let url = Self.resolveSavedBookmark() {
            self.state = .granted(url)
            self.activeScopedURL = url
        } else {
            self.state = .needsGrant
        }
    }

    /// Shows an NSOpenPanel preselected to ~/.claude/projects and saves the
    /// user's choice as a security-scoped bookmark.
    func requestAccess() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Grant TokenMeter read access to your Claude Code logs folder."
        panel.prompt = "Grant Access"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)

            // Start using the granted URL.
            if url.startAccessingSecurityScopedResource() {
                self.activeScopedURL = url
                self.state = .granted(url)
            }
        } catch {
            // Surface failure via state — caller can re-prompt.
            self.state = .needsGrant
        }
    }

    /// Forgets the saved permission. Useful for "switch folder" flows.
    func revoke() {
        if let active = activeScopedURL {
            active.stopAccessingSecurityScopedResource()
            activeScopedURL = nil
        }
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        state = .needsGrant
    }

    /// The URL the rest of the app should treat as the Claude logs root.
    /// Returns nil only when the sandbox needs a fresh grant.
    var rootURL: URL? {
        switch state {
        case .granted(let u):    return u
        case .unsandboxed(let u): return u
        case .needsGrant:        return nil
        }
    }

    // MARK: - Internal

    private static func resolveSavedBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale)
            if isStale {
                // Stale bookmark — user must re-grant. Drop it so we don't keep retrying.
                UserDefaults.standard.removeObject(forKey: bookmarkKey)
                return nil
            }
            guard url.startAccessingSecurityScopedResource() else { return nil }
            return url
        } catch {
            return nil
        }
    }
}
