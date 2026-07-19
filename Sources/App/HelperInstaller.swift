import Foundation
import ServiceManagement

/// Registers/unregisters the privileged daemon via `SMAppService.daemon(plistName:)`
/// (macOS 13+). No `SMJobBless`, no deprecated bless APIs.
@MainActor
final class HelperInstaller: ObservableObject {

    enum InstallState: Equatable {
        case notRegistered
        case requiresApproval
        case enabled
        case unknown(String)

        var userMessage: String {
            switch self {
            case .notRegistered:
                return "Helper not registered yet. Click Install."
            case .requiresApproval:
                return "Approval required — enable RouteMaster in System Settings › "
                     + "General › Login Items & Extensions, then relaunch."
            case .enabled:
                return "Helper installed and enabled."
            case .unknown(let s):
                return "Helper status: \(s)"
            }
        }
    }

    @Published private(set) var state: InstallState = .notRegistered

    private var service: SMAppService {
        SMAppService.daemon(plistName: HelperConstants.helperPlistName)
    }

    func refreshState() {
        state = Self.map(service.status)
    }

    /// Register the daemon. If macOS needs user approval, guide them to System Settings.
    func register() {
        do {
            try service.register()
            refreshState()
        } catch {
            // First-time registration commonly throws until the user approves the daemon
            // in Login Items. Re-read the authoritative status; if it is still not
            // enabled, treat it as "requires approval" and let the UI guide the user.
            refreshState()
            if state != .enabled {
                state = .requiresApproval
            }
        }
    }

    /// Unregister for clean dev iteration.
    func unregister() {
        try? service.unregister()
        refreshState()
    }

    /// Open the Login Items settings pane so the user can approve the daemon.
    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func map(_ status: SMAppService.Status) -> InstallState {
        switch status {
        case .notRegistered:   return .notRegistered
        case .enabled:         return .enabled
        case .requiresApproval:return .requiresApproval
        case .notFound:        return .notRegistered
        @unknown default:      return .unknown("\(status.rawValue)")
        }
    }
}
