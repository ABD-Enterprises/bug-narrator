import Foundation
@testable import BugNarrator

final class MockLaunchAtLoginService: LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus
    var setEnabledError: Error?

    init(status: LaunchAtLoginStatus = .disabled) {
        self.status = status
    }

    func currentStatus() -> LaunchAtLoginStatus {
        status
    }

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        if let setEnabledError {
            throw setEnabledError
        }

        status = enabled ? .enabled : .disabled
        return status
    }
}

