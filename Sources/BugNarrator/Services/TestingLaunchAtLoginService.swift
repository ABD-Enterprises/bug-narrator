import Foundation

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
