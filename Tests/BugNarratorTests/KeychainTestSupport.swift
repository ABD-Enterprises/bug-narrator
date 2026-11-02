import Foundation
import Darwin
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
///
/// The directory is one per run rather than one fixed path, so a token file
/// left by an earlier run is never picked up by a later one.
// nonisolated(unsafe) because the exit handler below reads it from a
// nonisolated context, and the suite is not concurrent.
private nonisolated(unsafe) var isolatedLocalServerInstallDirectoryToRemove: URL?

let isolatedLocalServerInstallDirectory: URL = {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "BugNarratorTests-LocalServerInstall-\(UUID().uuidString)",
            isDirectory: true
        )
    // The directory holds a token file, so it is removed when the suite's
    // process exits: a run must not leave one behind on the machine.
    isolatedLocalServerInstallDirectoryToRemove = directory
    atexit {
        if let directory = isolatedLocalServerInstallDirectoryToRemove {
            try? FileManager.default.removeItem(at: directory)
        }
    }
    return directory
}()

func makeIsolatedSettingsStore(
    defaults: UserDefaults,
    keychainService: KeychainServicing = MockKeychainService(),
    launchAtLoginService: any LaunchAtLoginControlling = MockLaunchAtLoginService(),
    legacyDefaultsDomains: [String]? = nil,
    localProviderReachabilityProbe: ((URL) -> Bool)? = { _ in false },
    localProviderSession: URLSession = .shared,
    localServerInstallDirectory: URL = isolatedLocalServerInstallDirectory,
    usesTheStoresOwnReachabilityProbe: Bool = false
) -> SettingsStore {
    SettingsStore(
        defaults: defaults,
        keychainService: keychainService,
        launchAtLoginService: launchAtLoginService,
        legacyDefaultsDomains: legacyDefaultsDomains,
        // The default refuses every host, so that an incidental test never
        // polls for a server it is not about. A test that is about the probe
        // itself asks for the store's own probe, which is the one that reads
        // the health check over `localProviderSession`.
        localProviderReachabilityProbe: usesTheStoresOwnReachabilityProbe
            ? nil
            : (localProviderReachabilityProbe ?? { _ in false }),
        localProviderSession: localProviderSession,
        localServerInstallDirectory: localServerInstallDirectory
    )
}
