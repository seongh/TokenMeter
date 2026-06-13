import Foundation
import ServiceManagement

/// Wraps SMAppService.mainApp for macOS 13+. Toggling this register/unregisters
/// the bundle so that it launches automatically on user login.
@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var statusDetail: String

    init() {
        let s = SMAppService.mainApp.status
        self.isEnabled = (s == .enabled)
        self.statusDetail = Self.describe(s)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            statusDetail = "Failed: \(error.localizedDescription)"
            return
        }
        let s = SMAppService.mainApp.status
        isEnabled = (s == .enabled)
        statusDetail = Self.describe(s)
    }

    static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered:        return "Not registered"
        case .enabled:              return "Enabled — will launch at login"
        case .requiresApproval:     return "Approval needed in System Settings ▸ Login Items"
        case .notFound:             return "Service not found"
        @unknown default:           return "Unknown state"
        }
    }
}
