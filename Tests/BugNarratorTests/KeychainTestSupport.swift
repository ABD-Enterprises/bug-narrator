import Foundation
@testable import BugNarrator

final class MockKeychainService: KeychainServicing {
    var values: [String: String] = [:]
    var setError: Error?
    var deleteError: Error?
    var interactionRequiredKeys: Set<String> = []
    private(set) var readRequests: [(service: String, account: String, allowInteraction: Bool)] = []

    func string(forService service: String, account: String, allowInteraction: Bool) throws -> String? {
        readRequests.append((service: service, account: account, allowInteraction: allowInteraction))

        let key = key(forService: service, account: account)
        if interactionRequiredKeys.contains(key), !allowInteraction {
            throw KeychainError.interactionRequired
        }

        return values[key]
    }

    func setString(_ value: String, service: String, account: String) throws {
        if let setError {
            throw setError
        }

        values[key(forService: service, account: account)] = value
    }

    func deleteValue(service: String, account: String) throws {
        if let deleteError {
            throw deleteError
        }
        values.removeValue(forKey: key(forService: service, account: account))
    }

    private func key(forService service: String, account: String) -> String {
        "\(service)::\(account)"
    }
}

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

