import XCTest
@testable import BugNarrator

final class AppBootstrapTests: XCTestCase {
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
