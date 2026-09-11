import XCTest
@testable import BugNarrator

@MainActor
final class AppBootstrapTests: XCTestCase {
    func testIsolatedBootstrapOwnsAnInertServerIndependentOfOtherInstallations() async throws {
        let runtime = AppRuntimeEnvironment(bundlePath: "/tmp/BugNarrator.app", environment: [
            "BUGNARRATOR_UI_TEST_MODE": "1",
            "BUGNARRATOR_UI_TEST_SAFE_SERVICES": "1",
            "BUGNARRATOR_SETTINGS_UI_SMOKE_SCOPE": UUID().uuidString
        ])
        let bootstrap = AppBootstrap(runtimeEnvironment: runtime)
        let root = try XCTUnwrap(bootstrap.isolatedStorageRootURL)
        defer {
            try? FileManager.default.removeItem(at: root)
            if let suite = bootstrap.isolatedDefaultsSuiteName { UserDefaults().removePersistentDomain(forName: suite) }
        }
        let unrelatedInstallation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: unrelatedInstallation) }
        try FileManager.default.createDirectory(at: unrelatedInstallation, withIntermediateDirectories: true)
        let unrelatedBinary = unrelatedInstallation.appendingPathComponent("bugnarrator-transcription")
        let sentinel = Data("existing installation must survive".utf8)
        try sentinel.write(to: unrelatedBinary)
        let existingManager = LocalTranscriptionManager(directory: unrelatedInstallation)
        XCTAssertTrue(existingManager.installed)
        let isolated = bootstrap.localTranscriptionManager
        XCTAssertEqual(isolated.directory, root.appendingPathComponent("LocalTranscription", isDirectory: true))
        XCTAssertFalse(isolated.installed)
        await isolated.discover()
        XCTAssertNil(isolated.package)
        isolated.installAndStart()
        isolated.start()
        isolated.remove()
        await isolated.shutdown()
        XCTAssertEqual(try Data(contentsOf: unrelatedBinary), sentinel)

        // Even a binary appearing inside the isolated directory cannot launch.
        try FileManager.default.createDirectory(at: isolated.directory, withIntermediateDirectories: true)
        try sentinel.write(to: isolated.executable)
        let seeded = LocalTranscriptionManager.isolated(directory: isolated.directory)
        XCTAssertTrue(seeded.installed)
        seeded.start()
        await waitUntil { !seeded.busy }
        XCTAssertFalse(seeded.running)
        XCTAssertTrue(seeded.message.contains("disabled in the isolated runtime"))
        seeded.remove()
        XCTAssertFalse(seeded.installed)
        XCTAssertEqual(try Data(contentsOf: unrelatedBinary), sentinel)
        #if DEBUG
        let appState = UITestRuntimeSupport.makeAppState(
            settingsStore: bootstrap.settingsStore,
            transcriptStore: bootstrap.transcriptStore,
            runtimeEnvironment: runtime,
            storageRootURL: root,
            localTranscriptionManager: isolated
        )
        XCTAssertTrue(appState.localTranscriptionManager === isolated)
        #endif
    }

    func testBootstrapUsesIsolatedStoresUnderXCTest() throws {
        let runtimeEnvironment = AppRuntimeEnvironment(
            bundlePath: "/tmp/BugNarrator.app",
            environment: [
                "XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration",
                "XCTestSessionIdentifier": "session:123"
            ]
        )

        let bootstrap = AppBootstrap(runtimeEnvironment: runtimeEnvironment)

        XCTAssertEqual(bootstrap.storageMode, .isolatedForTests)
        XCTAssertEqual(bootstrap.isolatedDefaultsSuiteName, "BugNarrator.XCTestHost.session-123")
        XCTAssertNotNil(bootstrap.isolatedStorageRootURL)
        XCTAssertTrue(
            bootstrap.isolatedStorageRootURL?.lastPathComponent.contains("BugNarrator-XCTestHost-session-123") == true
        )
        XCTAssertTrue(bootstrap.settingsStore.openAtStartupSupported)
        XCTAssertNil(bootstrap.settingsStore.openAtStartupStatusMessage)

        bootstrap.settingsStore.preferredModel = "gpt-test-model"

        let isolatedDefaults = try XCTUnwrap(
            UserDefaults(suiteName: try XCTUnwrap(bootstrap.isolatedDefaultsSuiteName))
        )
        XCTAssertEqual(isolatedDefaults.string(forKey: "settings.preferredModel"), "gpt-test-model")
    }

    func testBootstrapUsesProductionStoresOutsideXCTest() {
        let runtimeEnvironment = AppRuntimeEnvironment(
            bundlePath: "/Applications/BugNarrator.app",
            environment: [:]
        )

        let bootstrap = AppBootstrap(runtimeEnvironment: runtimeEnvironment)

        XCTAssertEqual(bootstrap.storageMode, .production)
        XCTAssertNil(bootstrap.isolatedDefaultsSuiteName)
        XCTAssertNil(bootstrap.isolatedStorageRootURL)
    }
}
