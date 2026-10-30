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


/// Incidental settings tests must not inherit production health polling.
/// Where the unit suite keeps the local transcription token.
///
/// The token file lives next to the managed server install, which is under
/// the user's Application Support directory. The suite must not read or write
/// that file: a test that depends on it depends on the machine, and a run
/// would leave a token behind on the developer's disk.
let isolatedLocalServerInstallDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("BugNarratorTests-LocalServerInstall", isDirectory: true)

func makeIsolatedSettingsStore(
    defaults: UserDefaults,
    keychainService: KeychainServicing = MockKeychainService(),
    launchAtLoginService: any LaunchAtLoginControlling = MockLaunchAtLoginService(),
    legacyDefaultsDomains: [String]? = nil,
    localProviderReachabilityProbe: ((URL) -> Bool)? = { _ in false },
    localProviderSession: URLSession = .shared,
    localServerInstallDirectory: URL = isolatedLocalServerInstallDirectory
) -> SettingsStore {
    SettingsStore(
        defaults: defaults,
        keychainService: keychainService,
        launchAtLoginService: launchAtLoginService,
        legacyDefaultsDomains: legacyDefaultsDomains,
        localProviderReachabilityProbe: localProviderReachabilityProbe ?? { _ in false },
        localProviderSession: localProviderSession,
        localServerInstallDirectory: localServerInstallDirectory
    )
}
