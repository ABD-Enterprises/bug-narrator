import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case notFound
    case unavailable

    var isEnabled: Bool {
        switch self {
        case .enabled, .requiresApproval:
            return true
        case .disabled, .notFound, .unavailable:
            return false
        }
    }

    var isAvailable: Bool {
        switch self {
        case .unavailable:
            return false
        case .disabled, .enabled, .requiresApproval, .notFound:
            return true
        }
    }

    var message: String? {
        switch self {
        case .disabled, .enabled:
            return nil
        case .requiresApproval:
            return "BugNarrator is enabled to open at login, but macOS still requires approval in System Settings > General > Login Items."
        case .notFound:
            return "Open at Startup is not registered with macOS yet. Turn it on to register BugNarrator as a Login Item."
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
        case .notFound:
            return "not_found"
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
            return .notFound
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
