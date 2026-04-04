import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    var isEnabled: Bool {
        switch self {
        case .enabled, .requiresApproval:
            return true
        case .disabled, .unavailable:
            return false
        }
    }

    var isAvailable: Bool {
        self != .unavailable
    }

    var message: String? {
        switch self {
        case .disabled, .enabled:
            return nil
        case .requiresApproval:
            return "BugNarrator is enabled to open at login, but macOS still requires approval in System Settings > General > Login Items."
        case .unavailable:
            return "Open at Startup is unavailable for this app copy. Install BugNarrator in Applications and use a signed build if you want BugNarrator to launch automatically."
        }
    }

    var logValue: String {
        switch self {
        case .disabled:
            return "disabled"
        case .enabled:
            return "enabled"
        case .requiresApproval:
            return "requires_approval"
        case .unavailable:
            return "unavailable"
        }
    }
}

protocol LaunchAtLoginControlling {
    func currentStatus() -> LaunchAtLoginStatus
    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus
}

struct SystemLaunchAtLoginService: LaunchAtLoginControlling {
    func currentStatus() -> LaunchAtLoginStatus {
        guard #available(macOS 13.0, *) else {
            return .unavailable
        }

        switch SMAppService.mainApp.status {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        guard #available(macOS 13.0, *) else {
            return .unavailable
        }

        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }

        return currentStatus()
    }
}

struct TestingLaunchAtLoginService: LaunchAtLoginControlling {
    func currentStatus() -> LaunchAtLoginStatus {
        .disabled
    }

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        enabled ? .enabled : .disabled
    }
}
