import XCTest
@testable import BugNarrator

final class AppRuntimeEnvironmentTests: XCTestCase {
    func testUITestEnvironmentEnablesIsolatedRuntimeAndLaunchFlags() {
        let environment = AppRuntimeEnvironment(
            bundlePath: "/Applications/BugNarrator.app",
            environment: [
                "BUGNARRATOR_UI_TEST_MODE": "1",
                "BUGNARRATOR_OPEN_SETTINGS_ON_LAUNCH": "1",
                "BUGNARRATOR_OPEN_SESSION_LIBRARY_ON_LAUNCH": "1",
                "BUGNARRATOR_OPEN_RECORDING_CONTROLS_ON_LAUNCH": "1",
                "BUGNARRATOR_SEED_SESSION_LIBRARY_UI_TEST_DATA": "1",
                "BUGNARRATOR_UI_TEST_SAFE_SERVICES": "1"
            ]
        )

        XCTAssertTrue(environment.isRunningBugNarratorUITest)
        XCTAssertTrue(environment.usesIsolatedRuntime)
        XCTAssertTrue(environment.shouldBypassSingleInstanceEnforcement)
        XCTAssertTrue(environment.shouldOpenSettingsOnLaunch)
        XCTAssertTrue(environment.shouldOpenSessionLibraryOnLaunch)
        XCTAssertTrue(environment.shouldOpenRecordingControlsOnLaunch)
        XCTAssertTrue(environment.shouldSeedSessionLibraryUITestData)
        XCTAssertTrue(environment.shouldUseDeterministicUITestServices)
    }

    func testTestIsolationScopeUsesSanitizedEnvironmentValue() {
        let environment = AppRuntimeEnvironment(
            bundlePath: "/Applications/BugNarrator.app",
            environment: [
                "XCTestSessionIdentifier": "Session / Smoke Test #1"
            ]
        )

        XCTAssertTrue(environment.isRunningUnderTests)
        XCTAssertEqual(environment.testIsolationScope, "Session-Smoke-Test-1")
    }

    func testLaunchAtLoginStatusCanBeSeededForUITests() {
        XCTAssertEqual(makeEnvironment(status: "enabled").testLaunchAtLoginStatus, .enabled)
        XCTAssertEqual(makeEnvironment(status: "requires_approval").testLaunchAtLoginStatus, .requiresApproval)
        XCTAssertEqual(makeEnvironment(status: "not_found").testLaunchAtLoginStatus, .notFound)
        XCTAssertEqual(makeEnvironment(status: "unavailable").testLaunchAtLoginStatus, .unavailable)
        XCTAssertEqual(makeEnvironment(status: "unexpected").testLaunchAtLoginStatus, .disabled)
    }

    private func makeEnvironment(status: String) -> AppRuntimeEnvironment {
        AppRuntimeEnvironment(
            bundlePath: "/Applications/BugNarrator.app",
            environment: ["BUGNARRATOR_TEST_LAUNCH_AT_LOGIN_STATUS": status]
        )
    }
}
