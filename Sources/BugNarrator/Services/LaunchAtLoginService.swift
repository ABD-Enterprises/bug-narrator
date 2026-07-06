import Foundation
import ServiceManagement

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
    let status: LaunchAtLoginStatus

    init(status: LaunchAtLoginStatus = .disabled) {
        self.status = status
    }

    func currentStatus() -> LaunchAtLoginStatus {
        status
    }

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        enabled ? .enabled : .disabled
    }
}
