import Foundation

struct AppBootstrap {
    enum StorageMode: Equatable {
        case production
        case isolatedForTests
    }

    let storageMode: StorageMode
    let settingsStore: SettingsStore
    let transcriptStore: TranscriptStore
    let isolatedDefaultsSuiteName: String?
    let isolatedStorageRootURL: URL?

    init(runtimeEnvironment: AppRuntimeEnvironment, fileManager: FileManager = .default) {
        let launchAtLoginService: any LaunchAtLoginControlling

        if runtimeEnvironment.usesIsolatedRuntime {
            let scope = runtimeEnvironment.testIsolationScope
            let defaultsSuiteName = "BugNarrator.XCTestHost.\(scope)"
            let defaults = UserDefaults(suiteName: defaultsSuiteName) ?? .standard
            defaults.removePersistentDomain(forName: defaultsSuiteName)

            let storageRootURL = fileManager.temporaryDirectory
                .appendingPathComponent("BugNarrator-XCTestHost-\(scope)", isDirectory: true)
            try? fileManager.removeItem(at: storageRootURL)
            try? fileManager.createDirectory(at: storageRootURL, withIntermediateDirectories: true)

            launchAtLoginService = TestingLaunchAtLoginService(
                status: runtimeEnvironment.testLaunchAtLoginStatus
            )
            self.storageMode = .isolatedForTests
            self.settingsStore = SettingsStore(
                defaults: defaults,
                keychainService: InMemoryKeychainService(),
                launchAtLoginService: launchAtLoginService,
                legacyDefaultsDomains: []
            )
            self.transcriptStore = TranscriptStore(
                fileManager: fileManager,
                storageURL: storageRootURL.appendingPathComponent("sessions.json")
            )
            self.isolatedDefaultsSuiteName = defaultsSuiteName
            self.isolatedStorageRootURL = storageRootURL
            return
        }

        launchAtLoginService = SystemLaunchAtLoginService()
        self.storageMode = .production
        self.settingsStore = SettingsStore(launchAtLoginService: launchAtLoginService)
        self.transcriptStore = TranscriptStore()
        self.isolatedDefaultsSuiteName = nil
        self.isolatedStorageRootURL = nil
    }
}

private final class InMemoryKeychainService: KeychainServicing {
    private var storedValues: [String: String] = [:]

    func string(forService service: String, account: String, allowInteraction: Bool) throws -> String? {
        storedValues[storageKey(service: service, account: account)]
    }

    func setString(_ value: String, service: String, account: String) throws {
        storedValues[storageKey(service: service, account: account)] = value
    }

    func deleteValue(service: String, account: String) throws {
        storedValues.removeValue(forKey: storageKey(service: service, account: account))
    }

    private func storageKey(service: String, account: String) -> String {
        "\(service)::\(account)"
    }
}
