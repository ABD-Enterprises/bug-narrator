import Foundation

protocol LaunchAtLoginControlling {
    func currentStatus() -> LaunchAtLoginStatus
    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus
}
